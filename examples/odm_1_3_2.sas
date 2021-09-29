/***********************************************************************************/
/* Study:         Standard program                                                 */
/* Program Name:  odm_1_3_2.sas                                                    */
/* Description:   Convert a standard ODM-xml file to SAS datasets parallel to      */
/*                define-xml conversion.                                           */
/*                Handles ItemRef as a special case for variables                  */
/***********************************************************************************/
/*  Copyright (c) 2020 Jørgen Mangor Iversen                                       */
/*                                                                                 */
/*  Permission is hereby granted, free of charge, to any person obtaining a copy   */
/*  of this software and associated documentation files (the "Software"), to deal  */
/*  in the Software without restriction, including without limitation the rights   */
/*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell      */
/*  copies of the Software, and to permit persons to whom the Software is          */
/*  furnished to do so, subject to the following conditions:                       */
/*                                                                                 */
/*  The above copyright notice and this permission notice shall be included in all */
/*  copies or substantial portions of the Software.                                */
/*                                                                                 */
/*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR     */
/*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,       */
/*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE    */
/*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER         */
/*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,  */
/*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE  */
/*  SOFTWARE.                                                                      */
/***********************************************************************************/

%macro odm_1_3_2(metalib = metalib, /* metadata libref                     */
                     odm = ,        /* odm-xml with full path              */
                  xmlmap = %str(odm_1_3_2_formedix.map),  /* XML Map with full path    */
                    lang = ,                              /* 2 letter Language, if any */
                   debug = );                             /* If any value, no clean up */

  %if %nrquote(&debug) ne %then %do;
	  %put MACRO:   &sysmacroname;
	  %put METALIB: &metalib;
	  %put ODM:     &odm;
	  %put XMLMAP:  &xmlmap;
    %put LANG:    &lang;
    %put DEBUG:   &debug;
  %end;

  /* Print a message to the log and terminate macro execution */
  %macro panic(msg);
    %put %sysfunc(cats(ER, ROR:)) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if %nrquote(&metalib) =  %then %let metalib=metalib;
  %if %nrquote(&odm)     =  %then %panic(No odm-xml file specified in parameter ODM=.);
  %if %nrquote(&xmlmap)  =  %then %panic(No XML Map file specified in the parameter XMLMAP=.);
  %if %sysfunc(libref(&metalib))         %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %sysfunc(fileexist("&odm"))    = 0 %then %panic(ODM-xml file "&odm" not found.);
  %if %sysfunc(fileexist("&xmlmap")) = 0 %then %panic(XMLMAP file "&xmlmap" not found.);
  %if %length(%nrquote(&lang)) = 0 or %length(%nrquote(&lang)) = 2 %then;
                                         %else %panic(Language "&lang" must be blank or a 2 letter code.);

  /* filename and libname are linked via the shared fileref/libref */
  filename odm    "&odm";
  filename xmlmap "&xmlmap" encoding="utf-8";
  libname  odm    xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

  /* Standard is always CRF in ODM-XML files */
  %let standard = crf;

  proc format;
    invalue dmvars
    'ACTARM'   = 1
    'ACTARMCD' = 1 
    'AGE'      = 1 
    'AGEU'     = 1 
    'ARM'      = 1 
    'ARMCD'    = 1 
    'BRTHDTC'  = 1 
    'COUNTRY'  = 1 
    'DTHFL'    = 1 
    'ETHNIC'   = 1 
    'RACE'     = 1 
    'RFENDTC'  = 1 
    'RFSTDTC'  = 1 
    'RFXENDTC' = 1 
    'SEX'      = 1 
    other      = 0;

    invalue relvars
    'APID'     = 1
    'POOLID'   = 1
    'IDVAR'    = 1
    'IDVARVAL' = 1
    'RELTYPE'  = 1
    'RELID'    = 1
    'RDOMAIN'  = 1
    other      = 0;
  run;

  /* ItemDefAlias contains SDTM annotations carrying dataset and variable names */
  %if %qsysfunc(exist(odm.ItemDefAlias)) %then %do;
    data _temp_annotations (drop=Name _:) _tokens(keep=_token);
      set odm.ItemDefAlias (keep=Name);
      length dataset $ 8 variable $ 32 _token $ 5000;
      length OrderNumber 8 CodeListOID MethodOID RoleCodeListOID CollectionExceptionConditionOID Comment $ 200;
      retain OrderNumber . CodeListOID MethodOID RoleCodeListOID CollectionExceptionConditionOID Comment '';

      /* Skip if no assignment operator at all */
      if index(Name, '=') = 0 then return;

      /* Break annotation into tokens separated by comma */
      do _i = 1 to count(Name, ',') + 1;
        _token = scan(Name, _i, ',', 'r');
        output _tokens;
        select;
          /* Skip if no assignment operator in token */
          when (index(_token, '=') = 0) leave;

          /* If a period is found in the first 9 characters, then token begins with dataset.variable */
          when (index(substr(_token, 1, min(9, length(_token))), '.') and first(reverse(_token) ne '.')) do;
            dataset  = left(scan(_token, 1, '.'));
            variable = left(scan(_token, 2, '.'));
            variable = substr(variable, 1, notalpha(variable) -1);
            if dataset = '' or variable = '' then do;
              put "SELECT OPTION: index(substr(_token, 1, length(_token))), '.')";
              put _ALL_;
            end; else
              output _temp_annotations;
          end;

          /* If an equals sign is found in the first 9 characters, then assume variable name and extract dataset from variable prefix */
          when (index(substr(compress(_token), 1, min(9, length(compress(_token)))), '=')) do;
            variable = left(scan(_token, 1, '='));
            dataset  = substr(variable, 1, 2);
            if input(variable,  dmvars.) then dataset = 'DM';
            if input(variable, relvars.) then dataset = 'RELREC';
            if dataset = '' or variable = '' then do;
              put "SELECT OPTION: index(substr(compress(_token), 1, length(_token))), '=')";
              put _ALL_;
            end; else
              output _temp_annotations;
          end;

          /* If only one equals sign and a period within 8 characters later, extract variable delimited by '.' and '=' */
          /* Extract dataset as the last word before the period */
          when (count(_token, '=') = 1 and 0 <= index(_token, '=') - index(_token, '.') <= 8) do;
            variable = left(scan(_token, 2, '.='));
            _token   = left(scan(_token, 1, '.'));
            dataset  = left(scan(_token, countw(_token)));
            if dataset = '' or variable = '' then do;
              put "SELECT OPTION: count(_token, '=') = 1 and index(_token, '=') - index(_token, '.') <= 8";
              put _ALL_;
            end; else
              output _temp_annotations;
          end;

          /* If only one equals sign, extract variable as the last word before the equals sign */
          /* Extract the dataset name as the variale prefix */
          when (count(_token, '=') = 1) do;
            _token   = left(scan(_token, 1, '='));
            variable = left(scan(_token, countw(_token, ' '), ' '));
            if index(variable, '.') then do;
              dataset  = scan(variable, 1);
              variable = scan(variable, 2);
            end; else
              dataset  = left(substr(left(variable), 1, 2));
            if input(variable,  dmvars.) then dataset = 'DM';
            if input(variable, relvars.) then dataset = 'RELREC';
            if dataset = '' or variable = '' then do;
              put "SELECT OPTION: count(_token, '=') = 1";
              put _ALL_;
            end;else
              output _temp_annotations;
          end;

          /* When more equal signs indicate more possible tokens */
         when (count(_token, '=') > 1) do;
           do _j = 1 to count(_token, '=');
             _token_sub = scan(_token, _j, '=');
             variable  = scan(_token_sub, -1, ' ');
             if index(variable, '.') then do;
               dataset  = scan(variable, 1);
               variable = scan(variable, 2);
             end; else
               dataset  = left(substr(left(variable), 1, 2));
             if input(variable,  dmvars.) then dataset = 'DM';
             if input(variable, relvars.) then dataset = 'RELREC';
             if dataset = '' or variable = '' then do;
               put "SELECT OPTION: count(_token, '=') > 1";
               put _ALL_;
             end;else
               output _temp_annotations;
            end;
          end;

          /* Dump to log and find new ways of annotation syntax */
          otherwise do;
            put "SELECT OPTION: otherwise";
            put _ALL_;
          end;
        end;
      end;
    run;

    proc sort data=_temp_annotations nodupkey;
      by dataset ordernumber variable;
    run;
  %end;

  /* Build metadata tables inspired by P21 template */
  proc sql noprint;
    /* Global metadata regarding one CRF snapshot and SDTM annotations */
 %if %qsysfunc(exist(odm.ODM)) %then %do;
    create table &metalib..&standard._study as select distinct
           odm.Description,
           odm.FileType,
           odm.Granularity,
           odm.Archival,
           odm.FileOID,
           odm.CreationDateTime,
           odm.PriorFileOID,
           odm.AsOfDateTime,
           odm.ODMVersion,
           odm.ID as SignatureID,
           study.StudyName,
           study.StudyDescription,
           study.ProtocolName,
           mdv.StudyOID,
           mdv.Name,
           mdv.Description as MetaDataVersionDescription,
           mdv.IncludeStudyOID,
           mvl.ProtocolDescription,
           mdv.IncludeMetaDataVersionOID,
           "&standard"    as StandardName,
           odm.ODMVersion as StandardVersion
      from odm.odm
      join odm.Study
        on odm.ID = STudy.ID
      join odm.Metadataversion mdv
        on Study.OID = mdv.StudyOID
      left join odm.MetaDataVersionLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                         mvl
        on mdv.StudyOID = mvl.StudyOID
       and mdv.OID      = mvl.OID
           ;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* Global definitions of measurement units */
  %if %qsysfunc(exist(odm.Studyunits)) %then %do;
    %let units = 0;
    select distinct count(*)
      into :units
      from odm.Studyunits;
     
    %if &units ne 0 %then %do;
    create table &metalib..&standard._studybasic as select distinct
           sun.StudyOID,
           sun.OID,
           sun.Name as MeasurementUnit,
           Symbol,
           Context,
           sua.Name as Alias
      from odm.Studyunits     sun
      join odm.Studyunitalias sua
        on sun.StudyOID = sua.StudyOID
       and sun.OID      = sua.OID;

      %if &sqlobs = 0 %then %do;
        drop table &syslast;
      %end;
    %end;
  %end;

    /* Very simple list of datasets from annotations */
  %if %qsysfunc(exist(odm.Itemgroupdef)) %then %do;
    create table &metalib..&standard._datasets as select distinct
           Domain as Dataset
      from odm.ItemGroupDef (where=(Domain ne ''))
     union select distinct Dataset
      from _temp_annotations (where=(Dataset ne ''))
     order by Dataset;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;

    create table &metalib..&standard._Sections as select distinct
           igd.OID,
           igd.Name,
           igd.Repeating,
           igd.IsReferenceData,
           igd.SASDatasetName,
           igd.Domain,
           igd.Origin,
           igd.Purpose,
           igd.Comment,
           igl.Description,
           Context,
           iga.Name as SectionAlias
      from odm.ItemGroupDef           igd
      left join odm.ItemGroupDefAlias iga
        on igd.MDVOID = iga.MDVOID
       and igd.OID    = iga.OID
      left join odm.ItemGroupDefLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                      igl
        on igd.MDVOID = igl.MDVOID
       and igd.OID    = igl.OID 
     order by igd.OID;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* Itemgroupdefitemref contains relationships between datasets and variables */
  %if %qsysfunc(exist(odm.ItemGroupDefItemRef)) %then %do;
    create table _temp_variables as select distinct
           var.OID,
           dsn.Domain        as Dataset,
           var.SDSVarName    as Variable,
           CodeListOID,
           MethodOID,
           var.Comment
      from odm.Itemgroupdefitemref rel
      join odm.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      join odm.Itemdef             var
        on rel.ItemOID = var.OID
     where Variable ne ''
      order by Dataset, Variable;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* P21 has codes and enumerated items combined */
  %if %qsysfunc(exist(odm.CodeList)) %then %do;
    create table &metalib..&standard._Codelists as select distinct
           cdl.OID                                    as ID,
           cdl.Name,
           cdl.Alias                                  as NCI_Codelist_Code,
           cdl.DataType                               as Data_Type,
           coalesce(itm.OrderNumber, enu.OrderNumber) as Order,
           coalescec(itm.CodedValue, enu.CodedValue)  as Term,
           coalescec(itm.Alias, enu.Alias)            as NCI_Term_Code,
           cll.Description,
           cil.Decode                                 as Decoded_Value
      from odm.CodeList                    cdl
      left join odm.CodeListLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                           cll
        on cdl.OID = cll.OID
      left join odm.CodeListItem           itm
        on itm.OID = cdl.OID
      left join odm.CodeListItemLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                           cil
        on itm.OID        = cil.OID
       and itm.CodedValue = cil.CodedValue
      left join odm.CodeListEnumeratedItem enu
        on enu.OID = cdl.OID
     order by ID,
           Term;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* Check if any dictionaries inside code lists */
  %if %qsysfunc(exist(odm.CodeList)) %then %do;
    %let dictionaries = 0;
    select distinct count(*)
      into :dictionaries
      from odm.Codelist
     where Dictionary ne '';
     
    %if &dictionaries ne 0 %then %do;
    create table &metalib..&standard._Dictionaries as select distinct
           OID as ID,
           Name,
           DataType as Data_Type,
           Dictionary,
           Version
      from odm.Codelist
     where Dictionary ne ''
     order by ID;

      %if &sqlobs = 0 %then %do;
        drop table &syslast;
      %end;
    %end;
  %end;

    /* Forms */
  %if %qsysfunc(exist(odm.FormDef)) %then %do;
    create table &metalib..&standard._Forms as select distinct
           fmd.MDVOID,
           fmd.OID,
           fmd.Name as Form,
           fmd.Repeating,
           fml.Description as FormDescription,
           fda.Context,
           fda.Name as FormAlias,
           fal.PdfFileName,
           fal.PresentationOID
      from odm.FormDef                   fmd
      left join odm.FormDefAlias         fda
        on fmd.MDVOID = fda.MDVOID
       and fmd.OID    = fda.OID
      left join odm.FormDefLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                         fml
        on fmd.MDVOID = fml.MDVOID
       and fmd.OID    = fml.OID
      left join odm.FormDefArchiveLayout fal
        on fmd.MDVOID = fal.MDVOID
       and fmd.OID    = fal.OID
     order by fmd.MDVOID, fmd.OID;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
 %end;

    /* Questions are mixed with SDTM variables in ItemDef */
  %if %qsysfunc(exist(odm.FormDefItemGroupRef)) %then %do;
    create table &metalib..&standard._Questions as select distinct
           fgr.MDVOID,
           fgr.OID,
           ItemGroupOID,
           ItemOID,
           igr.OrderNumber,
           igr.Mandatory,
           imd.Name,
           DataType,
           SDSVarName,
           itl.Description,
           qul.Description as Question,
           Dictionary,
           Version,
           Code,
           CodeListOID,
           Context,
           ida.Name as Alias
      from odm.FormDefItemGroupRef fgr
      join odm.ItemGroupDefItemRef igr
        on fgr.MDVOID       = igr.MDVOID
       and fgr.ItemGroupOID = igr.OID
      join odm.Itemdef             imd
        on igr.MDVOID       = imd.MDVOID
       and igr.ItemOID      = imd.OID
      left join odm.ItemDefAlias   ida
        on imd.MDVOID       = ida.MDVOID
       and imd.OID          = ida.OID
      left join odm.ItemDefLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                   itl
        on imd.MDVOID       = itl.MDVOID
       and imd.OID          = itl.OID
      left join odm.QuestionLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                    qul
        on imd.MDVOID       = qul.MDVOID
       and imd.OID          = qul.OID
     order by fgr.OID, ItemGroupOID, ItemOID;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* Visits */
  %if %qsysfunc(exist(odm.StudyEventDef)) %then %do;
    create table &metalib..&standard._Visits as select distinct
           sed.MDVOID,
           sed.OID         as VisitOID,
         %if %qsysfunc(exist(odm.ProtocolStudyEventRef)) %then .; %else psr.OrderNumber;
                            as VisitNum,
           sed.Name         as Visit,
         %if %qsysfunc(exist(odm.ProtocolStudyEventRef)) %then ' ';  %else psr.Mandatory;
                            as Mandatory length=200,
           sed.Repeating,
           sed.Type,
           sed.Category,
           sel.Description,
         %if %qsysfunc(exist(odm.ProtocolStudyEventRef)) %then ' ';  %else psr.CollectionExceptionConditionOID;
                            as CollectionExceptionConditionOID length=200
      from odm.StudyEventDef          sed
   %if %qsysfunc(exist(odm.ProtocolStudyEventRef)) %then %do;
      join odm.ProtocolStudyEventRef  psr
        on psr.MDVOID        = sed.MDVOID
       and psr.StudyEventOID = sed.OID
   %end;
      left join odm.StudyEventDefLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                      sel
        on sed.MDVOID = sel.MDVOID
       and sed.OID    = sel.OID
     order by sed.MDVOID, VisitNum;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;

    /* Visit Matrix */
  %if %qsysfunc(exist(odm.ProtocolStudyEventRef)) %then %do;
    create table &metalib..&standard._VisitMatrix as select distinct
           sed.MDVOID,
           sed.OID         as VisitOID,
           sfr.FormOID,
           sfr.OrderNumber as FormNumber,
           sfr.Mandatory   as FormIsMandatory,
           sfr.CollectionExceptionConditionOID
      from odm.StudyEventDef        sed
      join odm.StudyEventDefFormRef sfr
        on sed.MDVOID = sfr.MDVOID
       and sed.OID    = sfr.OID
     order by sed.MDVOID, FormNumber;

    %if &sqlobs = 0 %then %do;
      drop table &syslast;
    %end;
  %end;
  quit;

  %if %sysfunc(exist(_temp_variables)) %then %do;
    data _temp_variables_all;
      set _temp_variables _temp_annotations (keep=Dataset Variable CodelistOID MethodOID Comment);
      by Dataset Variable;
    run;
  
    data &metalib..&standard._Variables (drop=_:);
      set _temp_variables_all (rename=(OID=_OID CodelistOID=_CodeListOID MethodOID=_MethodOID Comment=_Comment));
      by  Dataset Variable;
      length OID CodeListOID MethodOID $ 200 Comment $ 500;
      retain OID CodeListOID MethodOID Comment '';
      if first.Variable then do;
        OID         = '';
        CodeListOID = '';
        MethodOID   = '';
        Comment     = '';
      end;
      OID         = catx(' ', OID,         _OID);
      MethodOID   = catx(' ', MethodOID,   _MethodOID);
      CodeListOID = catx(' ', CodeListOID, _CodeListOID);
      Comment     = catx(' ', Comment,     _Comment);
      if last.Variable;
    run;
  %end;

  %if %nrquote(&debug) = %then %do;
    /* Cleanup WORK */
    proc datasets lib=work nolist;
      delete _temp_: _tokens;
  quit;
    
    libname  odm clear;
    filename odm clear;
  %end;
%mend;

/*
Test statements:
libname metalib "C:\temp\metadata";
%odm_1_3_2(odm = %str(C:\temp\metadata\CDISC ODM 1.3.2.xml),
        xmlmap = %str(C:\temp\metadata\odm_1_3_2.map));

proc copy in=odm out=work;run;
*/