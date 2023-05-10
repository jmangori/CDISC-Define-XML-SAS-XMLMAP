/***********************************************************************************************/
/* Description: Convert a standard CDISC define-xml file to SAS. Works for any define-xml,     */
/*              both SDTM and ADaM. Creates datasets in METALIB prefixed by <standard>_        */
/*              extracted from first delimited word of XPATH:                                  */
/*              /ODM/Study/MetaDataVersion/@def:StandardName                                   */
/***********************************************************************************************/
/* MIT License                                                                                 */
/*                                                                                             */
/* Copyright (c) 2020-2023 Jørgen Mangor Iversen                                               */
/*                                                                                             */
/* Permission is hereby granted, free of charge, to any person obtaining a copy                */
/* of this software and associated documentation files (the "Software"), to deal               */
/* in the Software without restriction, including without limitation the rights                */
/* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell                   */
/* copies of the Software, and to permit persons to whom the Software is                       */
/* furnished to do so, subject to the following conditions:                                    */
/*                                                                                             */
/* The above copyright notice and this permission notice shall be included in all              */
/* copies or substantial portions of the Software.                                             */
/*                                                                                             */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR                  */
/* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,                    */
/* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE                 */
/* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER                      */
/* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,               */
/* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE               */
/* SOFTWARE.                                                                                   */
/***********************************************************************************************/

%macro define_2_0_0(metalib=metalib,                 /* metadata libref           */
                    define =,                        /* define-xml with full path */
                    xmlmap = %str(define_2_0_0.map), /* XML Map with full path    */
                    debug  = );                      /* If any value, no clean up */
  %if %nrquote(&debug) ne %then %do;
    %put MACRO:   &sysmacroname;
    %put METALIB: &metalib;
    %put DEFINE:  &define;
    %put XMLMAP:  &xmlmap;
  %end;

  /* Print a message to the log and terminate macro execution */
  %macro panic(msg);
    %put %sysfunc(cats(ER, ROR:)) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if "&metalib" = "" %then %let metalib=metalib;
  %if "&define"  = "" %then %panic(No define-xml file specified in parameter DEFINE=.);
  %if "&xmlmap"  = "" %then %panic(No XML Map file specified in the parameter XMLMAP=.)

  %if %sysfunc(libref(&metalib))         %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %sysfunc(fileexist("&define")) = 0 %then %panic(Define-xml file "&define" not found.);
  %if %sysfunc(fileexist("&xmlmap")) = 0 %then %panic(XMLMAP file "&xmlmap" not found.);

  /* filename and libname are linked via the shared fileref/libref */
  filename define "&define";
  filename xmlmap "&xmlmap" encoding="utf-8";
  libname  define xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

  /* Detect which standard from the short list of Allowable Values (Extensible) */
  %let standard =;
  proc sql noprint;
    select distinct lowcase(scan(StandardName, 1))
      into :standard
      from define.Study;
  quit;
  %let standard = %trim(&standard);
  %if &standard = %then %panic(No valid standard defined in define-xml file "&define".);

  /* Collect all variables part of simple or compound keys */
  proc sql;
    create table _temp_KeySequence as select distinct
           dsn.Name as Dataset,
           var.Name as Variable,
           KeySequence
      from define.ItemGroupDefItemRef rel
      join define.ItemGroupDef        dsn
        on rel.OID = dsn.OID
      join define.ItemDef             var
        on rel.ItemOID = var.OID
     where KeySequence ne .
     order by Dataset,
           KeySequence;
  quit;

  /* Build strings of simple or compound keys */
  data _temp_Key_Variables (keep=Dataset Key_Variables);
    set _temp_KeySequence;
    by  Dataset;
    length Key_Variables $ 200;
    retain Key_Variables '';
    if first.Dataset then Key_Variables = Variable;
    else Key_Variables = cats(Key_Variables, ',', Variable);
    if last.Dataset;
  run;

  /* Assemble all page refences into one combined variable, separated by commas */
  %macro pages(in=, out=);
    proc sort data=&in out=_temp_pages;
      by OID;
    run;
  
    data &out (keep=OID Pages);
      set _temp_pages;
      by OID;
      length Pages _pages $ 500;
      retain Pages '';
      if first.OID then
        Pages = '';
      if FirstPage ne '' and LastPage ne '' then
        _pages = cats(FirstPage, '-', LastPage);
      Pages = catx(',', Pages, _pages, PageRefs);
      if last.OID;
    run;
  %mend;

  /* Places where page refences are needed */
  %pages(in=define.ItemDefOrigin,         out=_temp_origin);
  %pages(in=define.MethodDefDocumentRef,  out=_temp_methods);
  %pages(in=define.CommentDefDocumentRef, out=_temp_comment);

  /* Obtain the length of the CheckValue variable, subject to change */
  %let CheckValue = 200;
  proc sql noprint;
    select length
      into :CheckValue
      from dictionary.columns
     where upcase(libname) = 'DEF'
       and upcase(memname) = 'WHERECLAUSEDEFCHECKVALUE'
       and upcase(name)    = 'CHECKVALUE';
  quit;

  /* Calculate the cardinality of CheckValues. */
  proc sql;
    create table _temp_cardinal as select distinct
           '_tmp_card'                    as fmtname,
           cats(OID, ItemOID, Comparator) as start,
           count(*)                       as label,
           'I'                            as type
      from define.WhereClauseDefCheckValue
     group by start;
  quit;

  proc format cntlin=_temp_cardinal;
  run;

  /* Separate CheckValue due to cardinality ambiguiety in the CDISC define-xml 2.0 definition document */
  data _temp_checkvalues;
    set define.WhereClauseDefCheckValue;
    Cardinality = input(cats(OID, ItemOID, Comparator), _tmp_card.);
    by OID /* ItemOID Comparator*/;
    Cardinality = input(cats(OID, ItemOID, Comparator), _tmp_card.);
    if Cardinality = . then Cardinality = 1;
    retain Order .;
    if first.OID /*or first.ItemOID or first.Comparator*/ then Order = 0;
    Order = Order + 1;
  run;

  /* Build metadata tables from P21 template */
  proc sql;
    /* Empty variables reflects system differences (Formedix-On/P21E) */
    create table &metalib..&standard._study as select distinct
           StudyName,
           StudyDescription,
           ProtocolName,
           StandardName,
           StandardVersion
      from define.Study;

    /* Join of datasets and strings of simple or compound keys */
    create table &metalib..&standard._datasets as select distinct
           Name as Dataset,
           Description,
           Class,
           Structure,
           Purpose,
           Key_Variables,
           Repeating,
           IsReferenceData as Reference_Data,
           CommentOID      as Comment
      from define.ItemGroupDef      dsn
      left join _temp_Key_Variables seq
        on dsn.Name = seq.Dataset
     order by Dataset;

    /* Itemgroupdefitemref contains relationships between datasets and variables */
    create table &metalib..&standard._Variables as select distinct
           OrderNumber       as Order,
           dsn.Name          as Dataset,
           var.Name          as Variable,
           var.Description   as Label,
           var.DataType      as Data_Type,
           Length,
           SignificantDigits as Significant_Digits,
           DisplayFormat     as Format,
           Mandatory,
           CodeListOID       as Codelist,
           OriginType        as Origin,
           Pages,
           MethodOID         as Method,
           var.Predecessor,
           Role,
           var.CommentOID    as Comment
      from define.ItemGroupDefItemRef rel
      join define.ItemGroupDef        dsn
        on rel.OID = dsn.OID
      join define.ItemDef             var
        on rel.ItemOID = var.OID
      left join _temp_origin          pag
        on var.OID = pag.OID
     order by Dataset,
           Order;

    /* Itemgroupdefitemref lags a proper key to Itemdef for transposed variables in SUPPQUAL */
    create table &metalib..&standard._ValueLevel as select distinct
           val.oid,
           val.ItemOID,
           val.OrderNumber           as Order,
           scan(val.ItemOID, 1, '.') as Dataset,
           scan(val.ItemOID, 2, '.') as Variable,
           WhereClauseOID            as Where_Clause,
           var.Description,
           var.DataType              as Data_Type,
           var.Length,
           var.SignificantDigits     as Significant_Digits,
           var.DisplayFormat         as Format,
           val.Mandatory,
           var.CodeListOID           as Codelist,
           var.OriginType            as Origin,
           Pages,
           val.MethodOID             as Method,
           var.Predecessor,
           var.CommentOID            as Comment
      from define.ValuelistDef        val
      join define.ItemDef             var
        on val.ItemOID = var.OID
      left join _temp_origin          pag
        on val.ItemOID = pag.OID
     order by Dataset,
           Variable,
           Order,
           Where_Clause;

    /* P21 lags logical operators (and/or). CheckValues has a different cardinality */
    create table &metalib..&standard._WhereClauses as select distinct
           whe.OID        as ID,
           dsn.Name       as Dataset,
           var.Name       as Variable,
           whe.Comparator,
           chv.CheckValue as Value,
           Cardinality,
           Order
      from define.WhereClauseDef      whe
      join define.ItemDef             var
        on whe.ItemOID = var.OID
      join define.ItemGroupDefItemRef rel
        on var.OID = rel.ItemOID
      join define.ItemGroupDef        dsn
        on rel.OID = dsn.OID
      left join _temp_checkvalues     chv
        on whe.OID        = chv.OID
       and whe.ItemOID    = chv.ItemOID
       and whe.Comparator = chv.Comparator
     order by ID,
           Order;

    /* P21 has codes and enumerated items combined */
    create table &metalib..&standard._Codelists as select distinct
           cdl.OID                                         as ID,
           cdl.Name,
           cdl.Alias                                       as NCI_Codelist_Code,
           cdl.DataType                                    as Data_Type,
           coalesce(itm.OrderNumber, enu.OrderNumber)      as Order,
           coalescec(itm.CodedValue, enu.CodedValue)       as Term,
           coalescec(itm.Alias, enu.Alias)                 as NCI_Term_Code,
           coalescec(itm.ExtendedValue, enu.ExtendedValue) as ExtendedValue,
           itm.Decode                                      as Decoded_Value
      from define.CodeList                    cdl
      left join define.CodeListItem           itm
        on itm.OID = cdl.OID
      left join define.CodeListEnumeratedItem enu
        on enu.OID = cdl.OID
     order by ID,
           Term;

    /* Straight forward */
    create table &metalib..&standard._Dictionaries as select distinct
           OID      as ID,
           Name,
           DataType as Data_Type,
           Dictionary,
           Version
      from define.CodeList
     where Dictionary ne ''
     order by ID;

    /* P21 has computatipnal methods and formal expressions combined */
    create table &metalib..&standard._Methods as select distinct
           met.OID              as ID,
           met.Name,
           met.Type,
           met.Description,
           for.Context          as Expression_Context,
           for.FormalExpression as Expression_Code,
           title                as Document,
           Pages
      from define.MethodDef                      met
      left join define.MethodDefFormalExpression for
        on met.OID = for.OID
      left join define.MethodDefDocumentRef      doc
        on doc.OID = met.OID
      left join define.StudyDocuments            stu
        on stu.ID = doc.leafID
      left join _temp_methods                    pag
        on pag.OID = met.OID
     order by ID;

    /* One comment per page reference */
    create table &metalib..&standard._Comments as select distinct
           com.OID as ID,
           Comment as Description,
           title,
           Pages
      from define.CommentDef                 com
      left join _temp_comment                pag
        on com.OID = pag.OID
      left join define.CommentDefDocumentRef ref
        on com.OID = ref.OID
      left join define.StudyDocuments        doc
        on ref.leafID = doc.ID
     order by ID;

    /* Simple list of referred documents */
    create table &metalib..&standard._Documents as select distinct
           ID,
           title,
           href
      from define.StudyDocuments
     order by ID;
  quit;

  /* Cleanup WORK */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _temp_:;
    quit;

    proc catalog catalog=work.formats;
      delete _tmp_card.infmt;
    quit;
  %end;
%mend;

/*
libname metalib "X:\Users\jmi\metadata";
%define_2_0_0(define = %str(X:\Users\jmi\metadata\SDTM Define-XML 2.0.xml),
             xmlmap  = %str(X:\Users\jmi\metadata\define_2_0_0.map));
%define_2_0_0(define = %str(X:\Users\jmi\metadata\ADaM Define-XML 2.0.xml),
             xmlmap  = %str(X:\Users\jmi\metadata\define_2_0_0.map));

proc copy in=define out=work;run;
*/
