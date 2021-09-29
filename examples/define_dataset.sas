/***********************************************************************************************/
/* Description: Create one well formed dataset from metadata according to a CDISC define-xml   */
/*              document. If no input dataset, an empty dataset is created                     */
/***********************************************************************************************/
/* Disclaimer:  This program is the sole property of LEO Pharma A/S and may not be copied or   */
/*              made available to any third party without prior written consent from the owner */
/***********************************************************************************************/

%include "%str(&_SASWS_./leo/development/library/utilities/panic.sas)";
%include "%str(&_SASWS_./leo/development/library/utilities/clength.sas)";
%include "%str(&_SASWS_./leo/development/library/metadata/define_emptydel.sas)";

%macro define_dataset(metalib =metalib, /* metadata libref           */
                      standard=,        /* standard (SDTM/ADaM/CRF)  */
                      dataset =,        /* dataset to create         */
                      indata  =,        /* input dataset             */
                      outlib  =work,    /* output dataset libref     */
                      trimdata=Y,       /* trim character variables  */
                      sortdata=Y,       /* sort output data          */
                      emptydel=Y,       /* remove empty variables    */
                      xptlib  =,        /* XPT libref, if any        */
                      debug   =);       /* Not blank preserves WORK */
  %put MACRO:    &sysmacroname;
  %put METALIB:  &metalib;
  %put STANDARD: &standard;
  %put DATASET:  &dataset;
  %put INDATA:   &indata;
  %put OUTLIB:   &outlib;
  %put TRIMDATA: &trimdata;
  %put SORTDATA: &sortdata;
  %put EMPTYDEL: &emptydel;
  %put XPTLIB:   &xptlib;
  %if %nrquote(&debug) ne %then
  %put DEBUG:    &debug;

  /* Validate parameters and set up default values */
  %if %nrquote(&metalib) =                   %then %let metalib = metalib;
  %if %qsysfunc(libref(&metalib))            %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %nrquote(&standard) =                  %then %panic(Standard not specified.);
  %let standard = %scan(&standard, 1);       /* Discard version numbers etc. */
  %if %qsysfunc(exist(&metalib..&standard._datasets)) = 0
                                             %then %panic(Standard %upcase(&standard) not found.);
  %if %nrquote(&dataset) =                   %then %panic(Dataset to create not specified.);
  %if %nrquote(&indata) = %then %do;
    %let sortdata = N;
    %let trimdata = N;
    %let emptydel = N;
  %end;
  %else %do;
    %let sortdata = %upcase(%substr(%left(&sortdata), 1, 1));
    %let trimdata = %upcase(%substr(%left(&trimdata), 1, 1));
    %let emptydel = %upcase(%substr(%left(&emptydel), 1, 1));
    %if &sortdata = Y or &sortdata = N %then;%else %panic(%str(Parameter SORTDATA must be one of y, Y, Yes, YES, n, N, No, NO.));
    %if &trimdata = Y or &trimdata = N %then;%else %panic(%str(Parameter TRIMDATA must be one of y, Y, Yes, YES, n, N, No, NO.));
    %if &emptydel = Y or &emptydel = N %then;%else %panic(%str(Parameter EMPTYDEL must be one of y, Y, Yes, YES, n, N, No, NO.));
    %if %index(&indata, .) %then %do;
      %let lib = %qscan(&indata, 1, .);
      %let mem = %qscan(&indata, 2, .);
      %if %qsysfunc(libref(&lib))            %then %panic(Libref %qupcase(&lib) not found.);
    %end;
    %else %do;
      %let lib = WORK;
      %let mem = &indata;
    %end;
    %let fileid = %qsysfunc(open(sashelp.vmember (where=(upcase(libname) = "%qupcase(&lib)" and upcase(memname) = "%qupcase(&mem)"))));
    %if &fileid = 0                          %then %panic(%qsysfunc(sysmsg()));
    %let found = %qsysfunc(fetch(&fileid));
    %let rc    = %qsysfunc(close(&fileid));
    %if &found                               %then %panic(Input data %qupcase(&lib..&mem) not found.);
  %end;
  %if %nrquote(&outlib) =                    %then %let outlib = work;
  %if %qsysfunc(libref(&outlib))             %then %panic(Output libref %upcase(&outlib) not found.);
  %if %nrquote(&xptlib) ne %then %do;
    %if %qsysfunc(libref(&xptlib))           %then %panic(XPT destination folder %upcase(&xptlib) not found.);
  %end;
  %if %sysfunc(exist(&metalib..&standard._variables)) = 0
                                             %then %panic(Standard %upcase(&standard) incomplete.);
  proc sql noprint;
    select *
      from &metalib..&standard._datasets
     where upcase(dataset) = upcase("&dataset");
  quit;
  %if &sqlobs = 0                            %then %panic(Dataset %upcase(&dataset) not found in standard %upcase(&standard).);

  /* Build sourcecode in a catalog entry to include later */
  %let catref = sas%scan(%sysevalf(%sysfunc(ranuni(-1)) * 10000), 1, .);
  filename &catref catalog "work.code.&sysmacroname..source";
  %if %nrquote(&debug) ne %then %do;
    %put NOTE: Created fileref &catref..;
  %end;

  /* Build a datastep for one dataset in metadata */
  data _null_;
    merge &metalib..&standard._datasets
          &metalib..&standard._variables;
    where upcase(dataset) = upcase("&dataset");;
    by dataset;
    file &catref;

    if first.dataset then
      put "data &outlib.." dataset '(label="' Description +(-1) '");';

    if data_type in ('text' 'partialDate' 'partialDatetime') or index(upcase(variable), 'DTC') then do;
      data_type = 'text';
      dollar    = '$';
      if length = . then length= 200;
    end;
    if data_type in ('date' 'datetime' 'float' 'integer') then length = 8;
    if length = . then length = 8;
    if upcase("&trimdata") ne "Y" and data_type = 'text' then length = 200;
    put "  attrib" @10 variable @19 "length=" dollar length @;
    if format ne '' then put @32 "format=" format @;
    put @49 "label='" label +(-1) "';";

    if last.dataset then do;
      if "&indata" = "" then put '  stop;';
      else put "  set &indata;";
      put 'run;';
      if upcase("&trimdata") = "Y" then
        put '%' "clength(data=&outlib.." dataset +(-1) ");";
      if upcase("&sortdata") = "Y" then do;
        put "proc sort data=&outlib.." dataset +(-1) ';';
        key_variables = translate(key_variables, ' ', ',');
        put ' by ' key_variables +(-1) ';';
        put 'run;';
      end;
      if upcase("&emptydel") = "Y" then
        put '%' "define_emptydel(metalib=&metalib, standard=&standard, debug=&debug, dataset=&outlib.." dataset +(-1) ");";
      if "&xptlib" ne "" then
        put "proc copy in=&outlib. out=&xptlib;select " dataset +(-1) ";run;";
    end;
  run;

  %include &catref;

  /* Clean up */
   %if %nrquote(&debug) = %then %do;
     filename &catref clear;
   %end;
   %else %do;
     %put NOTE: Remember to clean up fileref &catref..;

     data _null_;
       infile &catrefx dsd;
       input;
       if _N_ = 1 then put 'Generated code to generate one dataset';
       put _INFILE_;
     run;
   %end;
%mend define_dataset;

/*
libname metalib       "&_SASWS_./leo/clinical/lp9999/8888/metadata/data";
libname sdtm          "&_SASWS_./leo/clinical/lp9999/8888/sdtm/data";
libname raw     xport "&_SASWS_./leo/clinical/lp9999/8888/received/raw/dm.xpt";
libname sdtmxpt xport "&_SASWS_./leo/clinical/lp9999/8888/sdtm/data/xpt/dm.xpt";
%define_dataset(dataset=dm,standard=sdtm,outlib=sdtm,indata=raw.dm,xptlib=sdtmxpt);
%define_dataset(dataset=dm,standard=sdtm,outlib=sdtm,indata=raw.dm,emptydel=N);
*/