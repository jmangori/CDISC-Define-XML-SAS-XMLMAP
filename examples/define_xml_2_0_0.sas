/***********************************************************************************************/
/* Description: Build a define-xml from datasets created by macro define_2_0_0.sas             */
/*              Works for any define-xml, both SDTM and ADaM. Reads datasets in METALIB        */
/*              prefixed by <standard>_. Default values are best guesses, not in datasets      */
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

%macro define_xml_2_0_0(metalib=metalib,              /* metadata libref                */
                       standard=sdtm,                 /* Generate SDTM/ADaM define      */
                         define=,                     /* define-xml with full path      */
                        FileOID=,                     /* Standard/study name            */
                     Originator=define_xml_2_0_0.sas, /* This program                   */
                   SourceSystem=,                     /* For refence when relevant      */
            SourceSystemVersion=,                     /* For refence when relevant      */
                     ODMVersion=1.3.2,                /* Not to be changed meaningfully */
                       StudyOID=DEFINE_1,             /* STD_* : standard SDY_* : study */
             MetaDataVersionOID=MDVOID_1,             /* Identify asset group           */
                        StdName=,                     /* Normally standard IG name      */
                 StdDescription=,                     /* Long standard og IG name       */ 
                          debug= );                   /* If any value, no clean up      */
  %if %nrquote(&debug) ne %then %do;
    %put MACRO:               &sysmacroname;
    %put METALIB:             &metalib;
    %put STANDARD:            &standard;
    %put DEFINE:              &define;
    %put FILEOID:             &FileOID;
    %put ORIGINATOR:          &Originator;
    %put SOURCESYSTEM:        &SourceSystem;
    %put SOURCESYSTEMVERSION: &SourceSystemVersion;
    %put ODMVERSION:          &ODMVersion;
    %put STUDYOID:            &StudyOID;
    %put METADATAVERSIONOID:  &MetaDataVersionOID;
    %put STDNAME:             &StdName;
    %put STDDESCRIPTION:      &StdDescription;
  %end;

  /* Print a message to the log and terminate macro execution */
  %macro panic(msg);
    %put %sysfunc(cats(ER, ROR:)) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if %nrquote(&metalib)  = %then %let metalib=metalib;
  %if %nrquote(&standard) = %then %let standard=sdtm;
  %if %nrquote(&define)   = %then %panic(No define-xml file specified in parameter DEFINE=.);
  %if %qsysfunc(libref(&metalib)) %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %qsysfunc(exist(&metalib..&standard._Study))     = 0
   or %qsysfunc(exist(&metalib..&standard._Documents)) = 0
   or %qsysfunc(exist(&metalib..&standard._Datasets))  = 0
   or %qsysfunc(exist(&metalib..&standard._Variables)) = 0
      %then %panic(Datasets for standard "&standard" not found in library "&metalib".);

  /* Get the data values for default values */
  proc sql %if %nrquote(&debug) = %then noprint;;
    select coalescec(StudyName, ProtocolName),
           StandardVersion
      into :name,
           :StandardVersion trimmed
      from &metalib..&standard._Study;
  quit;
  /* Default values not in the parameter definitions i.e. data dependent */
  %if %nrquote(&FileOID) = %then %do;
    %let FileOID = &name;
    %if &name = %then %let FileOID = Test_define;
  %end;
  %if %nrquote(&StdName) = %then
    %let StdName = %qupcase(&standard) &StandardVersion;
  %if %nrquote(&StdDescription) = %then
    %let StdDescription = &StdName;

  /* Get global reference to SDTM annotated CRF, if present */
  %if %qsysfunc(exist(&metalib..&standard._Documents)) %then %do;
    proc sql %if %nrquote(&debug) = %then noprint;;
      select ID
        into :crfleafid trimmed
        from  &metalib..&standard._Documents
       where href = 'acrf.pdf';
    quit;
  %end;

  filename define "&define" new;

  /* Define-xml header to be closed at the end */
  data _null_;
    set &metalib..&standard._Study;
    file define recfm=v;
    datetime   = catx('T', put(date(), yymmdd10.), put(time(), time.));
    StudyName        = htmlencode(StudyName);
    StudyDescription = htmlencode(StudyDescription);
    ProtocolName     = htmlencode(ProtocolName);
    put @01 '<?xml version="1.0" encoding="UTF-8"?>';
    put @01 '<ODM';
    put @03 'xmlns:def="http://www.cdisc.org/ns/def/v2.0"';
    put @03 'xmlns:xlink="http://www.w3.org/1999/xlink"';
    put @03 'xmlns:arm="http://www.cdisc.org/ns/arm/v1.0"';
    put @03 'xmlns="http://www.cdisc.org/ns/odm/v1.3"';
    put @03 'FileOID="' "&FileOID" '"';
    put @03 'FileType="Snapshot"';
    put @03 'CreationDateTime="' datetime +(-1) '"';
    put @03 'AsOfDateTime="' datetime +(-1) '"';
    if "&Originator"          ne "" then put @03 'Originator="'          "&Originator"          '"';
    if "&SourceSystem"        ne "" then put @03 'SourceSystem="'        "&SourceSystem"        '"';
    if "&SourceSystemVersion" ne "" then put @03 'SourceSystemVersion="' "&SourceSystemVersion" '"';
    put @03 'ODMVersion="' "&ODMVersion" '">';
    put @03 '<Study OID="' "&StudyOID" '">';
    put @05 '<GlobalVariables>';
    if StudyName        ne '' then put @07 '<StudyName>'        StudyName +(-1)        '</StudyName>';
    if StudyDescription ne '' then put @07 '<StudyDescription>' StudyDescription +(-1) '</StudyDescription>';
    if ProtocolName     ne '' then put @07 '<ProtocolName>'     ProtocolName +(-1)     '</ProtocolName>';
    put @05 '</GlobalVariables>';
    put @05 '<MetaDataVersion OID="' "&MetaDataVersionOID" '"';
    put @07 'Name="' "&StdName" '"';
    put @07 'Description="' "&StdDescription" '"';
    put @07 'def:DefineVersion="2.0.0"';
    put @07 'def:StandardName="'    StandardName    +(-1) '"';
    put @07 'def:StandardVersion="' StandardVersion +(-1) '">';
  run;

  filename define "&define" mod;

  /* Document references */
  %if %qsysfunc(exist(&metalib..&standard._Documents)) %then %do;
    data _null_;
      set &metalib..&standard._Documents;
      file define recfm=v;
      /* SDTM annotated CRF if present */
      if href = 'acrf.pdf' then do;
        put @07 '<def:AnnotatedCRF>';
        put @09 '<def:DocumentRef leafID="' ID +(-1) '"/>';
        put @07 '</def:AnnotatedCRF>';
      end; else do;
        put @07 '<def:SupplementalDoc>';
        put @09 '<def:DocumentRef leafID="' ID +(-1) '"/>';
        put @07 '</def:SupplementalDoc>';
      end;
    run;
  %end;

  /* def:ValueListDef = Values */
  %if %qsysfunc(exist(&metalib..&standard._ValueLevel)) %then %do;
    proc sort data=&metalib..&standard._ValueLevel out=_temp_define_ValueLevel;
      by OID;
    run;

    data _null_;
      set _temp_define_ValueLevel;
      by OID;
      file define recfm=v;
      if first.OID then put @07 '<def:ValueListDef OID="' OID +(-1) '">';
      put @09 '<ItemRef ItemOID="' ItemOID +(-1) '" Mandatory="' Mandatory +(-1) '" OrderNumber="' Order +(-1) @;
      if Method ne '' then put '" MethodOID="' Method +(-1) @;
      put '">';
      if Where_Clause ne '' then put @11 '<def:WhereClauseRef WhereClauseOID="' Where_Clause +(-1) '"/>';
      put @09 '</ItemRef>';
      if last.OID then put @07 '</def:ValueListDef>';
    run;
  %end;

  /* def:WhereClauseDef - Where Clauses */
  %if %qsysfunc(exist(&metalib..&standard._WhereClauses)) %then %do;
    proc sql;
      create table _temp_define_wherevalue as select distinct
             &standard._WhereClauses.*,
             Comment
        from &metalib..&standard._WhereClauses
       inner join  &metalib..&standard._ValueLevel
          on Where_Clause = ID
       order by ID, Order;
    quit;

/*     if cardinality > 1 then create one rangecheck having many checkvalues */
/*     if cardinality = 1 then create a rangecheck having one checkvalue per value */
    data _null_;
      set _temp_define_wherevalue;
      by ID dataset variable notsorted;
      file define recfm=v;
      if first.ID then do;
        put @07 '<def:WhereClauseDef OID="' ID +(-1) @;
        if Comment ne '' then put '" def:CommentOID="' Comment +(-1) @;
        put '">';
      end;
      if first.Dataset or first.Variable = 1 then
        put @09 '<RangeCheck SoftHard="Soft" Comparator="' Comparator +(-1) '" def:ItemOID="' dataset +(-1) '.' variable +(-1) '">';
      if Value = '' then put @11 '<CheckValue/>';
                    else put @11 '<CheckValue>' Value +(-1) '</CheckValue>';
      if last.Dataset or last.Variable = 1 then
        put @09 '</RangeCheck>';
      if last.ID then do;
        put @07 '</def:WhereClauseDef>';
      end;
    run;
  %end;

  /* ItemGroupDef - Datasets */
  data _temp_define_fmtkeys;
    set &metalib..&standard._datasets (keep=dataset Key_Variables) end=tail;
    fmtname = 'keyseq';
    type    = 'I';
    do label = 1 to countw(Key_Variables);
      start = cats(dataset, '.', scan(Key_Variables, label));
      output;
    end;
    if tail then do;
      hlo   = '';
      start = '';
      label = 0;
      output;
    end;
  run;

  proc format cntlin=_temp_define_fmtkeys;
  run;

  data _null_;
    merge &metalib..&standard._Datasets  (rename=(description=dslabel))
          &metalib..&standard._Variables;
    by Dataset;
    file define recfm=v;
    location     = cats(lowcase(dataset), '.xpt');
    Key_Sequence = left(put(input(cats(dataset, '.', variable), ??keyseq.), 5.));
    ord          = left(put(Order, 5.));
    if first.dataset then do;
      put @07 '<ItemGroupDef OID="' dataset +(-1) '" Name="' dataset +(-1) '" Repeating="' repeating +(-1) '" IsReferenceData="'
          Reference_Data +(-1) '" SASDatasetName="' dataset +(-1) '" Domain="' dataset +(-1) '" Purpose="' Purpose +(-1)
          '" def:Structure="' Structure +(-1) '" def:Class="' Class +(-1) '" def:ArchiveLocationID="LF.' dataset +(-1) '">';
      put @09 '<Description>';
      put @11 '<TranslatedText>' dslabel +(-1) '</TranslatedText>';
      put @09 '</Description>';
    end;
    put @09 '<ItemRef ItemOID="' dataset +(-1) '.' variable +(-1) '" Mandatory="' Mandatory +(-1) '" OrderNumber="' ord +(-1) '" Role="' role +(-1) @;
    if key_sequence ne '.' then put '" KeySequence="' key_sequence +(-1) @;
    if Method       ne  '' then put '" MethodOID="'   Method       +(-1) @;
    put '"/>';
    if last.dataset then do;
      put @09 '<def:leaf ID="LF.' dataset +(-1) '" xlink:href="' location +(-1) '">';
      put @11 '<def:title>' location +(-1) '</def:title>';
      put @09 '</def:leaf>';
      put @07 '</ItemGroupDef>';
    end;
  run;

  /* ItemDef - Variables */
  proc sql;
    create table _temp_define_values_vloid as select distinct
           a.*,
           oid
      from      &metalib..&standard._Variables  a
      left join &metalib..&standard._ValueLevel b
        on a.dataset  = b.dataset
       and a.variable = b.variable
     order by a.Dataset, a.Variable;
  quit;

  data _null_;
/*     set &metalib..&standard._Variables; */
    set _temp_define_values_vloid;
    file define recfm=v;
    if anyalpha(Pages) then
      reftype = 'NamedDestination';
    else
      reftype = 'PhysicalRef';
    len = left(put(Length, 5.));
    dig = left(put(Significant_Digits, 5.));
/*     if codelist ne '' then Length = '200'; */
    put @07 '<ItemDef OID="' dataset +(-1) '.' variable +(-1) '" Name="' Variable +(-1) '" DataType="' Data_Type +(-1) @;
    if Length ne . then put '" Length="' len +(-1) @;
    put '" SASFieldName="' Variable +(-1) @;
    if Significant_Digits ne .  then put '" SignificantDigits="' dig     +(-1) @;
    if Comment            ne '' then put '" def:CommentOID="'    Comment +(-1) @;
    put '">';
    put @09 '<Description>';
    put @11 '<TranslatedText>' Label +(-1) '</TranslatedText>';
    put @09 '</Description>';
    put @09 '<def:Origin Type="' Origin +(-1) '">';
    if Origin = 'CRF' then do;
      put @11 '<def:DocumentRef leafID="' "&crfleafid" '">';
      put @13 '<def:PDFPageRef Type="' reftype +(-1) '" PageRefs="' Pages +(-1) '"/>';
      put @11 '</def:DocumentRef>';
    end;
    if Origin = 'Predecessor' then do;
      put @11 '<Description>';
      put @13 '<TranslatedText>' Predecessor +(-1) '</TranslatedText>';
      put @11 '</Description>';
    end;
    put @09 '</def:Origin>';
    if CodeList ne '' then put @09 '<CodeListRef CodeListOID="' CodeList +(-1) '"/>';
    if variable = 'QVAL' then put @09 '<def:ValueListRef ValueListOID="VL.' dataset +(-1) '.' variable +(-1) '"/>';
    put @07 '</ItemDef>';
  run;

  /* ItemDef - Values */
  %if %qsysfunc(exist(&metalib..&standard._ValueLevel)) %then %do;
    data _null_;
      set &metalib..&standard._ValueLevel;
      file define recfm=v;
      Name        = scan(ItemOID, 3);
      Description = htmlencode(Description);
      if anyalpha(Pages) then
        reftype = 'NamedDestination';
      else
        reftype = 'PhysicalRef';
      len = left(put(Length, 5.));
      put @07 '<ItemDef OID="' ItemOID +(-1) '" Name="' Name +(-1) '" DataType="' data_type +(-1)
          '" Length="' len +(-1) '" SASFieldName="' Name +(-1) @;
      if Comment ne '' then put '" def:CommentOID="' Comment +(-1) @;
      put '">';
      put @09 '<Description>';
      put @11 '<TranslatedText>' Description +(-1) '</TranslatedText>';
      put @09 '</Description>';
      if Codelist ne '' then put @09 '<CodeListRef CodeListOID="' Codelist +(-1) '"/>';
      put @09 '<def:Origin Type="' Origin +(-1) '">';
      if Origin = 'CRF' then do;
        put @11 '<def:DocumentRef leafID="' "&crfleafid" '">';
        put @13 '<def:PDFPageRef Type="' reftype +(-1) '" PageRefs="' Pages +(-1) '"/>';
        put @11 '</def:DocumentRef>';
      end;
      if Origin = 'Predecessor' then do;
        put @11 '<Description>';
        put @13 '<TranslatedText>' Predecessor +(-1) '</TranslatedText>';
        put @11 '</Description>';
      end;
      put @09 '</def:Origin>';
      put @07 '</ItemDef>';
    run;
  %end;

  /* CodeList - Codelists */
  %if %qsysfunc(exist(&metalib..&standard._CodeLists)) %then %do;
    proc sql;
      create table _temp_define_codelists as select *
        from &metalib..&standard._CodeLists a
       where not exists (select *
                           from &metalib..&standard._Dictionaries b
                          where a.ID = b.ID)
         and Decoded_Value ne ''
       order by ID;
    quit;

    data _null_;
      set _temp_define_codelists;
      by ID;
      file define recfm=v;
      Name          = htmlencode(Name);
      Decoded_Value = htmlencode(Decoded_Value);
      Term          = htmlencode(Term);
      ord           = left(put(Order, 5.));
      if first.ID then put @07 '<CodeList OID="' ID +(-1) '" Name="' Name +(-1) '" DataType="' Data_Type +(-1) '">';
      put @09 '<CodeListItem CodedValue="' Term +(-1) '" OrderNumber="' ord +(-1) @;
      if ExtendedValue ne '' then put '" def:ExtendedValue="' ExtendedValue +(-1) @;
      put '">';
      put @11 '<Decode>';
      put @13 '<TranslatedText>' Decoded_Value +(-1) '</TranslatedText>';
      put @11 '</Decode>';
      if NCI_Term_Code ne '' then put @11 '<Alias Name="' NCI_Term_Code +(-1) '" Context="nci:ExtCodeID"/>';
      put @09 '</CodeListItem>';
      if last.ID then do;
        if NCI_Codelist_Code ne '' then put @09 '<Alias Name="' NCI_Codelist_Code +(-1) '" Context="nci:ExtCodeID"/>';
        put @07 '</CodeList>';
      end;
    run;

  /* CodeList - Ennumerated */
    proc sql;
      create table _temp_define_ennumerated as select *
        from &metalib..&standard._CodeLists a
       where not exists (select *
                           from &metalib..&standard._Dictionaries b
                          where a.ID = b.ID)
         and Decoded_Value = ''
       order by ID;
    quit;

    data _null_;
      set _temp_define_ennumerated;
      by ID;
      file define recfm=v;
      Name          = htmlencode(Name);
      Decoded_Value = htmlencode(Decoded_Value);
      Term          = htmlencode(Term);
      ord           = left(put(Order, 5.));
      if first.ID then put @07 '<CodeList OID="' ID +(-1) '" Name="' Name +(-1) '" DataType="' Data_Type +(-1) '">';
      put @09 '<EnumeratedItem CodedValue="' Term +(-1) '" OrderNumber="' ord +(-1) @;
      if ExtendedValue ne '' then put '" def:ExtendedValue="' ExtendedValue +(-1) @;
      put '">';
      if NCI_Term_Code ne '' then put @11 '<Alias Name="' NCI_Term_Code +(-1) '" Context="TSVALNF"/>';
      put @09 '</EnumeratedItem>';
      if last.ID then do;
        if NCI_Codelist_Code ne '' then put @09 '<Alias Name="' NCI_Codelist_Code +(-1) '" Context="nci:ExtCodeID"/>';
        put @07 '</CodeList>';
      end;
    run;
  %end;

  /* CodeList - Dictionaries */
  %if %qsysfunc(exist(&metalib..&standard._Dictionaries)) %then %do;
    data _null_;
      set &metalib..&standard._Dictionaries;
      file define recfm=v;
      Name = htmlencode(Name);
      put @07 '<CodeList OID="' ID +(-1) '" Name="' Name +(-1) '" DataType="' Data_Type +(-1) '">';
      put @09 '<ExternalCodeList Dictionary="' Dictionary +(-1) '" Version="' Version +(-1) '"/>';
      put @07 '</CodeList>';
    run;
  %end;

  /* MethodDef - Methods */
  %if %qsysfunc(exist(&metalib..&standard._Methods)) %then %do;
    data _null_;
      set &metalib..&standard._Methods;
      file define recfm=v;
      Name               = htmlencode(Name);
      Description        = htmlencode(Description);
      Expression_Context = htmlencode(Expression_Context);
      Expression_Code    = htmlencode(Expression_Code);
      put @07 '<MethodDef OID="' ID +(-1) '" Name="' Name +(-1) '" Type="' Type +(-1) '">';
      put @09 '<Description>';
      put @11 '<TranslatedText>' Description +(-1) '</TranslatedText>';
      put @09 '</Description>';
      if compress(Expression_Context, Expression_Code) ne '' then
        put @09 '<FormalExpression Context="' Expression_Context +(-1) '">' Expression_Code +(-1) '</FormalExpression>';
      put @07 '</MethodDef>';
    run;
  %end;

  /* CommentDef - Comments */
  %if %qsysfunc(exist(&metalib..&standard._Comments)) %then %do;
    data _null_;
      set &metalib..&standard._Comments;
      file define recfm=v;
      Description = htmlencode(Description);
      put @07 '<def:CommentDef OID="' ID +(-1) '">';
      put @09 '<Description>';
      put @11 '<TranslatedText>' Description +(-1) '</TranslatedText>';
      put @09 '</Description>';
      put @07 '</def:CommentDef>';
    run;
  %end;

  /* Document definitions */
  %if %qsysfunc(exist(&metalib..&standard._Documents)) %then %do;
    data _null_;
      set &metalib..&standard._Documents;
      file define recfm=v;
      Title = htmlencode(Title);
      put @07 '<def:leaf ID="' ID +(-1) '" xlink:href="' href +(-1) '">';
      put @09 '<def:title>' Title +(-1) '</def:title>';
      put @07 '</def:leaf>';
    run;
  %end;

  /* Define-xml bottom closure */
  data _null_;
    set &metalib..&standard._Study;
    file define recfm=v;
    put @05 '</MetaDataVersion>';
    put @03 '</Study>';
    put @01 '</ODM>';
  run;

  filename define clear;

  /* Clean-up */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _temp_define_:;
    quit;
  %end;
%mend;

/*
libname metalib "X:\Users\jmi\metadata";
%let study = TEST01;

%define_xml_2_0_0(define = %str(X:\Users\jmi\metadata\sdtm\&study._define.xml),
                standard = SDTM,
                 FileOID = define_&study.,
            SourceSystem = define_xml_2_0_0,
                StudyOID = SDY_&study.,
      MetaDataVersionOID = AG_&study.);

%define_xml_2_0_0(define = %str(X:\Users\jmi\metadata\adam\&study._define.xml),
                standard = ADaM,
                 FileOID = define_&study.,
            SourceSystem = define_xml_2_0_0,
                StudyOID = SDY_&study.,
      MetaDataVersionOID = AG_&study.);
*/
