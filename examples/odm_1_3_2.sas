/***********************************************************************************************/
/* Description: Convert an odm-xml file made by Formedix to SAS. Extract CRF definitions from  */
/*              the ODM-XML file including SDTM definition from annotations                    */
/*              Handles ItemRef as a special case for variables. Extracts visit schedule       */
/***********************************************************************************************/
/* Disclaimer:  This program is the sole property of LEO Pharma A/S and may not be copied or   */
/*              made available to any third party without prior written consent from the owner */
/***********************************************************************************************/

%include "%str(&_SASWS_./leo/development/library/utilities/panic.sas)";

%macro odm_1_3_2(metalib = metalib,                       /* Metadata libref           */
                     odm = ,                              /* ODM-XML with full path    */
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

  /* Flatten ItemDef for variables having multiple attributes (codelists)
  proc sort data=odm.Itemdef out=temp_Itemdef (keep=OID SDSVarName Origin CodeListOID Comment);
    by    SDSVarName;
    where SDSVarName ne '';
  run;

  data temp_Itemdef_flat (drop=_:);
    set temp_Itemdef (rename=(OID=_OID Origin=_Origin CodelistOID=_CodeListOID Comment=_Comment));
    by  SDSVarName;
    length OID Origin CodeListOID $ 200 Comment $ 500;
    retain OID Origin CodeListOID Comment '';
    if first.SDSVarName then do;
      OID         = '';
      Origin      = '';
      CodeListOID = '';
      Comment      = '';
    end;
    OID         = catx(' ', OID,         _OID);
    Origin      = catx(' ', Origin,      _Origin);
    CodeListOID = catx(' ', CodeListOID, _CodeListOID);
    Comment     = catx(' ', Comment,     _Comment);
    if last.SDSVarName;
  run; */

  /* Prepare Formedix namespace tables */
  %if %qsysfunc(exist(odm.FormDefFormedix)) %then %do;
    /* Make sure expected data exist by creating dummys */
    data _temp_FormDefFormedix_fixvars;
      set odm.FormDefFormedix;
      output;
      if _N_ = 1 then do;
        MDVOID         = '';
        OID            = '';
        SetNamespace   = '';
        SetDisplayName = '';
        SetVersion     = .;
        Value          = '';
        Name           = 'HeaderStyle';
        DisplayName    = Name;
        output;
        Name           = 'Title';
        DisplayName    = Name;
        output;
        Name           = 'NotesTop';
        DisplayName    = Name;
        output;
      end;
    run;
    proc sort data=_temp_FormDefFormedix_fixvars out=_temp_FormDefFormedix;
      by OID Name;
    run;
    proc transpose data=_temp_FormDefFormedix out=_temp_FormDeffdx (where=(OID ne '') drop=_:);
      by      OID;
      id      Name;
      idlabel DisplayName;
      var     Value;
    run;
    %if &sysnobs = 0 %then %do;
      proc datasets lib=work nolist;
        delete _temp_FormDefFormedix_fixvars _temp_FormDefFormedix _temp_FormDeffdx;
      quit;
    %end;
  %end;
  
  %if %qsysfunc(exist(odm.ItemDefFormedix)) %then %do;
    /* Make sure expected data exist by creating dummys */
    data _temp_ItemDefFormedix_fixvars;
      set odm.ItemDefFormedix;
      output;
      if _N_ = 1 then do;
        MDVOID         = '';
        OID            = '';
        SetNamespace   = '';
        SetDisplayName = '';
        SetVersion     = .;
        Value          = '';
        Name           = 'DesignNotes';
        DisplayName    = Name;
        output;
        Name           = 'Notes';
        DisplayName    = Name;
        output;
        Name           = 'Display';
        DisplayName    = Name;
        output;
      end;
    run;
    proc sort data=_temp_ItemDefFormedix_fixvars out=_temp_ItemDefFormedix;
      by OID Name;
    run;
    proc transpose data=_temp_ItemDefFormedix out=_temp_ItemDeffdx (where=(OID ne '') drop=_:);
      by      OID;
      id      Name;
      idlabel DisplayName;
      var     Value;
    run;
    %if &sysnobs = 0 %then %do;
      proc datasets lib=work nolist;
        delete _temp_ItemDefFormedix_fixvars _temp_ItemDefFormedix _temp_ItemDeffdx;
      quit;
    %end;
  %end;
  
  %if %qsysfunc(exist(odm.CodeListFormedix)) %then %do;
    /* Make sure expected data exist by creating dummys */
    data _temp_CodeListFormedix_fixvars;
      set odm.CodeListFormedix;
      output;
      if _N_ = 1 then do;
        MDVOID         = '';
        OID            = '';
        SetNamespace   = '';
        SetDisplayName = '';
        SetVersion     = .;
        Value          = '';
        Name           = 'ExtCodeID';
        DisplayName    = Name;
        output;
        Name           = 'CodeListExtensible';
        DisplayName    = Name;
        output;
        Name           = 'CodeListDescription';
        DisplayName    = Name;
        output;
        Name           = 'PreferredTerm';
        DisplayName    = Name;
        output;
        Name           = 'CDISCSubmissionValue';
        DisplayName    = Name;
        output;
        Name           = 'CDISCSynonym';
        DisplayName    = Name;
        output;
        Name           = 'StandardName';
        DisplayName    = Name;
        output;
        Name           = 'StandardVersion';
        DisplayName    = Name;
        output;
      end;
    run;
    proc sort data=_temp_CodeListFormedix_fixvars out=_temp_CodeListFormedix;
      by OID Name;
    run;
    %if &sysnobs > 0 %then %do;
      proc transpose data=_temp_CodeListFormedix out=_temp_CodeListfdx (drop=_:);
        by      OID;
        id      Name;
        idlabel DisplayName;
        var     Value;
      run;
    %end;
    %else %do;
      proc datasets lib=work nolist;
        delete _temp_CodeListFormedix_fixvars _temp_CodeListFormedix;
      quit;
    %end;
  %end;
 
  %if %qsysfunc(exist(odm.CodeListItemFormedix)) %then %do;
    /* Handle multiple Values for Custom Attributes. Concatenate separated by semicolon */
    proc sort data=odm.CodeListItemFormedix out=_temp_CodeListItemFormedix;
      by MDVOID OID CodedValue Namespace NamespaceDisplayName Version Name DisplayName;
    run;    
    proc transpose data=_temp_CodeListItemFormedix out=_temp_CodeListItemFormedix_mval (drop=_:);
      by  MDVOID OID CodedValue Namespace NamespaceDisplayName Version Name DisplayName;
      var Value;
    run;
    proc sql noprint;
      select count(*)
        into :cols trimmed
        from dictionary.columns
       where upcase(libname) = 'WORK'
         and upcase(memname) = "%upcase(_temp_CodeListItemFormedix_mval)"
         and upcase(substr(name, 1, 3)) = 'COL';
    quit;
    %if %nrquote(&debug) ne %then %put &=cols;
    data _temp_CLItemFormedix_mval (drop=col:);
      set _temp_CodeListItemFormedix_mval;
      length Value $ 5000;
      array col[*] col1-col&cols;
      do coli = 1 to &cols;
        Value = catx(';', Value, col[coli]);
      end;
    run;
    /* Make sure expected data exist by creating dummys */
    data _temp_CLItemFormedix_fixvars;
      set _temp_CLItemFormedix_mval;
      output;
      if _N_ = 1 then do;
        MDVOID               = '';
        OID                  = '';
        Namespace            = '';
        NamespaceDisplayName = '';
        Version              = .;
        Value                = '';
        Name                 = 'ExtCodeID';
        DisplayName          = Name;
        output;
        Name                 = 'CDISCDefinition';
        DisplayName          = Name;
        output;
        Name                 = 'PreferredTerm';
        DisplayName          = Name;
        output;
        Name                 = 'CDISCSynonym';
        DisplayName          = Name;
        output;
      end;
    run;
    proc sort data=_temp_CLItemFormedix_fixvars out=_temp_CodeListItemFormedix;
      by OID CodedValue Name;
    run;
    %if &sysnobs > 0 %then %do;
      proc transpose data=_temp_CodeListItemFormedix out=_temp_CodeListItemfdx (drop=_:);
        by      OID CodedValue;
        id      Name;
        idlabel DisplayName;
        var     Value;
      run;
    %end;
    %else %do;
      proc datasets lib=work nolist;
        delete _temp_CodeListItemFormedix_fixvars _temp_CodeListItemFormedix;
      quit;
    %end;
  %end;

  /* Build metadata tables inspired by P21 template */
  proc sql noprint;
    /* Global metadata regarding one CRF snapshot and SDTM annotations */
 %if %qsysfunc(exist(odm.ODM)) %then %do;
   create table &metalib..&standard._Study as select distinct
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
      from odm.ODM
      join odm.Study
        on odm.ID = Study.ID
      join odm.MetaDataVersion           mdv
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
    create table &metalib..&standard._Studybasic as select distinct
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
    create table &metalib..&standard._Datasets as select distinct
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

    /* ItemGroupDefItemRef contains relationships between datasets and variables      */
  %if %qsysfunc(exist(odm.ItemGroupDefItemRef)) %then %do;
    create table _temp_variables as select distinct
           var.OID,
           dsn.Domain        as Dataset,
           var.SDSVarName    as Variable,
           CodeListOID,
           MethodOID,
           var.Comment
      from odm.ItemGroupDefItemRef rel
      join odm.ItemGroupDef        dsn
        on rel.OID = dsn.OID
      join odm.ItemDef             var
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
         %if %sysfunc(exist(_temp_CodeListfdx)) %then %do;
           ,
           fdx.ExtCodeID,
           fdx.CodeListExtensible,
           fdx.CodeListDescription,
           fdx.PreferredTerm,
           fdx.CDISCSubmissionValue,
           fdx.CDISCSynonym
         %end;
         %if %sysfunc(exist(_temp_CodeListItemfdx)) %then %do;
           ,
           ifx.CDISCDefinition
         %end;
      from odm.CodeList                    cdl
      left join odm.CodeListLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                           cll
        on cdl.OID         = cll.OID
      left join odm.CodeListItem           itm
        on itm.OID         = cdl.OID
      left join odm.CodeListItemLang
         %if %nrquote(&lang) ne %then %do; (where=(upcase(lang) in ('', "%qupcase(&lang)"))) %end;
                                           cil
        on itm.OID         = cil.OID
       and itm.CodedValue  = cil.CodedValue
      left join odm.CodeListEnumeratedItem enu
        on enu.OID = cdl.OID
         %if %sysfunc(exist(_temp_CodeListfdx)) %then %do;
      left join _temp_CodeListfdx          fdx
        on cdl.OID         = fdx.OID
         %end;
         %if %sysfunc(exist(_temp_CodeListItemfdx)) %then %do;
       left join _temp_CodeListItemfdx     ifx
         on itm.OID        = ifx.OID
        and itm.CodedValue = ifx.CodedValue
         %end;
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
         %if %sysfunc(exist(_temp_FormDeffdx)) %then %do;
           ,
           fdx.Title,
           fdx.DesignNotes,
           fdx.NotesTop
         %end;
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
         %if %sysfunc(exist(_temp_FormDeffdx)) %then %do;
      left join _temp_FormDeffdx         fdx
        on fmd.OID = fdx.OID
         %end;
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
         %if %sysfunc(exist(_temp_ItemDeffdx)) %then %do;
           ,
           fdx.DesignNotes,
           fdx.Notes,
           fdx.Display
         %end;
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
         %if %sysfunc(exist(_temp_ItemDeffdx)) %then %do;
      left join _temp_ItemDeffdx   fdx
        on imd.OID = fdx.OID
         %end;
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
      length OID CodeListOID MethodOID Comment $ 500;
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
LSAF:
libname metalib "&_SASWS_./leo/clinical/lp9999/8888/metadata/data";
%odm_1_3_2(odm = %str(&_SASWS_./leo/clinical/lp9999/8888/metadata/CDISC_ODM_1.3.2_visit.xml),
           xmlmap = %str(&_SASWS_./leo/development/library/metadata/odm_1_3_2_formedix.map));

%odm_1_3_2(metalib=work,
               odm=%str(&_SASWS_./leo/clinical/lp9999/8888/metadata/1401 Version 7 Draft.xml),
            xmlmap=%str(&_SASWS_./leo/development/library/metadata/odm_1_3_2_formedix.map), debug=n);
%odm_1_3_2(metalib=work,
               odm=%str(&_SASWS_./leo/clinical/lp9999/8888/metadata/LP0133-1401 - Metdata Version 297.xml),
            xmlmap=%str(&_SASWS_./leo/development/library/metadata/odm_1_3_2.map), lang=en);
%odm_1_3_2(metalib=work,
               odm=%str(&_SASWS_./leo/clinical/lp9999/8888/metadata/ct/nci_ct_v4.xml),debug=x,
            xmlmap=%str(&_SASWS_./leo/development/library/metadata/odm_1_3_2_formedix.map));
 */     