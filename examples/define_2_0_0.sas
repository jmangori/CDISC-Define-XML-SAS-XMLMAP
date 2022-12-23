/***********************************************************************************************/
/* Description: Convert a standard CDISC define.xml file to SAS. Works for any define-xml,     */
/*              both SDTM and ADaM. Creates datasets in METALIB prefixed by <standard>_        */
/*              extracted from first delimited word of XPATH:                                  */
/*                 /ODM/Study/MetaDataVersion/@def:StandardName                                */
/***********************************************************************************************/
/* Disclaimer:  This program is the sole property of LEO Pharma A/S and may not be copied or   */
/*              made available to any third party without prior written consent from the owner */
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
           dsn.name as Dataset,
           var.Name as Variable,
           KeySequence
      from define.Itemgroupdefitemref rel
      join define.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      join define.Itemdef             var
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

  /* Assemble all page refences into one combined variable */
  %macro pages(in=, out=);
  proc sort data=&in out=_temp_pages;
    by OID;
  run;

  data &out (keep= OID Pages);
    set _temp_pages;
    by OID;
    length Pages $ 500;
    retain Pages '';
    if first.OID then do;
      Pages = '';
      link pages;
    end;
    else link pages;
    if last.OID;
    return;
  pages:
      if PageRefs  ne '' then Pages = cats(Pages, PageRefs);
      if PageRefs  ne '' and cats(FirstPage, LastPage) ne ''
                         then Pages = cats(Pages, ',');
      if FirstPage ne '' then Pages = cats(Pages, FirstPage);
      if FirstPage ne '' and LastPage ne ''
                         then Pages = cats(Pages, '-');
      if LastPage  ne '' then Pages = cats(Pages, LastPage);
  run;
  %mend;

  /* Places where page refences are needed */
  %pages(in=define.Itemdeforigin,         out=_temp_origin);
  %pages(in=define.Methoddefdocumentref,  out=_temp_methods);
  %pages(in=define.Commentdefdocumentref, out=_temp_comment);

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

  /* Calculate the cardinality of CheckValues. Missing indicates cardinality=1 */
  proc sql;
    create table _temp_cardinal as select distinct
           OID,
           ItemOID,
           Comparator,
           count(*) as Cardinality
      from define.WhereClauseDefCheckValue
     group by OID,
           ItemOID,
           Comparator
    having cardinality > 1;

    create table _temp_cardinal_checkvalue as select distinct
           wcl.*,
           cardinality
      from define.WhereClauseDefCheckValue wcl
      left join _temp_cardinal             car
        on wcl.OID        = car.OID
       and wcl.ItemOID    = car.ItemOID
       and wcl.Comparator = car.Comparator
     order by wcl.OID,
           wcl.ItemOID,
           wcl.Comparator;
  quit;

  /* Resolve cardinality uniformally for cardinalities > 1                    */
  /* NOTE: incorrect where clauses of VAR1 IN ('SENTENCE OF MORE WORDS')      */
  /*       will be split into test for each word, not for the whole sentence. */
  /*       use the EQ Comparator for that. The same applies for NOTIN.        */
  data _temp_cardinal_multi (keep=OID ItemOID Comparator CheckValue);
    set _temp_cardinal_checkvalue;
    where cardinality = . and Comparator in ('IN' 'NOTIN');
    length _CheckValue $ &CheckValue;
    _CheckValue = CheckValue;
    do i = 1 to countw(_CheckValue, ' ');
      CheckValue = scan(_CheckValue, i, ' ');
      output;
    end;
  run;

  /* Prepare for merge */
  proc sort data=define.WhereclausedefCheckValue out=_temp_whereclausedefcheckvalue;
    by OID ItemOID Comparator;
  run;

  /* Separate CheckValue due to cardinality ambiguiety in the CDISC define.xml 2.0 definition document */
  data _temp_checkvalues;
    merge _temp_whereclausedefcheckvalue
          _temp_cardinal_multi
          _temp_cardinal;
    by OID ItemOID Comparator;
    if Cardinality = . then Cardinality = 1;
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
      from define.Itemgroupdef      dsn
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
           cdl.Name          as Codelist,
           OriginType        as Origin,
           Pages,
           MethodOID         as Method,
           var.Predecessor,
           Role,
           var.CommentOID    as Comment
      from define.Itemgroupdefitemref rel
      join define.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      join define.Itemdef             var
        on rel.ItemOID = var.OID
      left join define.Codelist       cdl
        on CodeListOID = cdl.OID
      left join _temp_origin          pag
        on var.OID = pag.OID
     order by Dataset,
           Order;

    /* Itemgroupdefitemref lags a proper key to Itemdef for transposed variables in SUPPQUAL */
    create table &metalib..&standard._valuelevel as select distinct
           val.ItemOID,
           val.OrderNumber       as Order,
           dsn.Name              as Dataset,
           var.SASFieldName      as Variable,
           WhereClauseOID        as Where_Clause,
           des.Description,
           var.DataType          as Data_Type,
           var.Length,
           var.SignificantDigits as Significant_Digits,
           var.DisplayFormat     as Format,
           val.Mandatory,
           cdl.Name              as Codelist,
           var.OriginType        as Origin,
           Pages,
           val.MethodOID         as Method,
           var.Predecessor,
           var.CommentOID        as Comment
      from define.Valuelistdef        val
      join define.Itemdef             var
        on val.ItemOID = var.OID
      join define.Itemgroupdefitemref rel
        on rel.ItemOID = catx('.', scan(var.oid, 1, '.'), scan(var.oid, 2, '.'))
      join define.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      left join define.Itemdef        des
        on catx('.', dsn.Name, var.SASFieldName) = var.OID
      left join define.Codelist       cdl
        on var.CodeListOID = cdl.OID
      left join _temp_origin          pag
        on rel.ItemOID = pag.OID
     order by Dataset,
           Variable,
           Order,
           Where_Clause;

    /* P21 lags logical operators (and/or). CheckValues has a different cardinality */
    create table &metalib..&standard._whereclauses as select distinct
           whe.OID    as ID,
           dsn.Name   as Dataset,
           var.Name   as Variable,
           whe.Comparator,
           chv.CheckValue as Value,
           Cardinality
      from define.Whereclausedef      whe
      join define.Itemdef             var
        on whe.ItemOID = var.OID
      join define.Itemgroupdefitemref rel
        on var.OID = rel.ItemOID
      join define.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      left join _temp_checkvalues     chv
        on whe.OID        = chv.OID
       and whe.ItemOID    = chv.ItemOID
       and whe.Comparator = chv.Comparator
     order by ID,
           Dataset,
           Variable,
           whe.Comparator,
           Value;

    /* P21 has codes and enumerated items combined */
    create table &metalib..&standard._Codelists as select distinct
           cdl.OID                                    as ID,
           cdl.Name,
           cdl.Alias                                  as NCI_Codelist_Code,
           cdl.DataType                               as Data_Type,
           coalesce(itm.OrderNumber, enu.OrderNumber) as Order,
           coalescec(itm.CodedValue, enu.CodedValue)  as Term,
           coalescec(itm.Alias, enu.Alias)            as NCI_Term_Code,
           itm.Decode                                 as Decoded_Value
      from define.CodeList                    cdl
      left join define.CodeListItem           itm
        on itm.OID = cdl.OID
      left join define.CodeListEnumeratedItem enu
        on enu.OID = cdl.OID
     order by ID,
           Term;

    /* Straight forward */
    create table &metalib..&standard._Dictionaries as select distinct
           OID as ID,
           Name,
           DataType as Data_Type,
           Dictionary,
           Version
      from define.Codelist
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
      from define.Methoddef                      met
      left join define.Methoddefformalexpression for
        on met.OID = for.OID
      left join define.Methoddefdocumentref      doc
        on doc.OID = met.OID
      left join define.Studydocuments            stu
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
      from define.Commentdef                 com
      left join _temp_comment                pag
        on com.OID = pag.OID
      left join define.Commentdefdocumentref ref
        on com.OID = ref.OID
      left join define.Studydocuments        doc
        on ref.leafID = doc.ID
     order by ID;

    /* Simple list of referred documents */
    create table &metalib..&standard._Documents as select distinct
           ID,
           title,
           href
      from define.Studydocuments
     order by ID;
  quit;

  /* Cleanup WORK */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _temp_:;
    quit;
  %end;
%mend;

/*
LSAF:
libname metalib "&_SASWS_./leo/clinical/lp9999/8888/metadata/data";
%define_2_0_0(define = %str(&_SASWS_./leo/clinical/lp9999/8888/metadata/SDTM Define-XML 2.0 with CDISC Stylesheet.xml),
              xmlmap = %str(&_SASWS_./leo/development/library/metadata/define_2_0_0.map));
%define_2_0_0(define = %str(&_SASWS_./leo/clinical/lp9999/8888/metadata/ADaM Define-XML 2.0 with CDISC Stylesheet.xml),
              xmlmap = %str(&_SASWS_./leo/development/library/metadata/define_2_0_0.map));

SAS:
libname metalib "X:\Users\leo0jxm\metadata";
%define_2_0_0(define = %str(X:\Users\leo0jxm\metadata\SDTM Define-XML 2.0.xml),
             xmlmap  = %str(X:\Users\leo0jxm\metadata\define_2_0_0.map));
%define_2_0_0(define = %str(X:\Users\leo0jxm\metadata\ADaM Define-XML 2.0.xml),
             xmlmap  = %str(X:\Users\leo0jxm\metadata\define_2_0_0.map));

proc copy in=define out=work;run;
*/
