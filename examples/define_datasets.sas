/***********************************************************************************/
/* Description: Create well formed datasets from metadata according to a CDISC     */          
/*              define-xml document. Like-named CDISC datasets are used as inputs. */
/*              If no input dataset, an empty dataset is created. If a program     */
/*              exists "&pgmpath/<dataset>.sas", the program is %included.         */
/*              Programs can read from raw.<dataset> without issuing a libname     */
/*              statement. Programs are expected to deliver work.<dataset>         */
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

%include "%str(&_SASWS_./leo/development/library/utilities/relpath.sas)";
%include "%str(&_SASWS_./leo/development/library/utilities/repo_ws_exists.sas)";
%include "%str(&_SASWS_./leo/development/library/utilities/repo_ws_children.sas)";
%include "%str(&_SASWS_./leo/development/library/metadata/define_dataset.sas)";

%macro define_datasets(metalib =metalib, /* metadata libref          */
                       standard=,        /* standard (sdtm/adam/crf) */
                       dataset =,        /* create only one dataset  */
                       inlib   =,        /* input SAS dataset libref */
                       inpath  =,        /* input XPT dataset path   */
                       outlib  =,        /* output dataset libref    */
                       trimdata=Y,       /* trim character variables */
                       sortdata=Y,       /* sort output data         */
                       emptydel=Y,       /* remove empty variables   */
                       xptpath =,        /* XPT path, if any         */
                       pgmpath =,        /* folder of dataset pgms   */
                       debug   =);       /* If any value, no clean up */
  %if %nrquote(&debug) ne %then %do;
  %put MACRO:    &sysmacroname;
  %put METALIB:  &metalib;
  %put STANDARD: &standard;
  %put DATASET:  &dataset;
  %put INLIB:    &inlib;
  %put INPATH:   &inpath;
  %put OUTLIB:   &outlib;
  %put TRIMDATA: &trimdata;
  %put SORTDATA: &sortdata;
  %put EMPTYDEL: &emptydel;
  %put XPTPATH:  &xptpath;
  %put PGMPATH:  &pgmpath;
  %end;

  /* Validate parameters and set up default values */
  %if %nrquote(&metalib) =                 %then %let metalib = metalib;
  %if %qsysfunc(libref(&metalib))          %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %nrquote(&standard) =                %then %panic(Standard not specified.);
  %let standard = %scan(&standard, 1);   /* Discard version numbers etc. */
  %if %sysfunc(exist(&metalib..&standard._datasets)) = 0
                                           %then %panic(Standard %sysfunc(lowcase(&standard)) not found.);
  %if %nrquote(&dataset) ne %then %do;
    proc sql noprint;
      select *
        from &metalib..&standard._datasets
       where upcase(dataset) = upcase("&dataset");
    quit;
    %if &sqlobs = 0                        %then %panic(Dataset %upcase(&dataset) not defined in metadata.);
  %end;
  %if %nrquote(&inlib) = and %nrquote(&inpath) = %then %let inlib = work;
  %if %nrquote(&inlib) ne and %nrquote(&inpath) ne
                                           %then %panic(Only one of INLIB= and INPATH= must be specified.);
  %if %nrquote(&inlib) ne %then
    %if %qsysfunc(libref(&inlib))          %then %panic(Input library %upcase(inlib) not found.)
  %if %nrquote(&inpath) ne %then %do;
    %repo_ws_exists(lsaf_path=&inpath);
    %if &_repo_ws_exists_ = 0              %then %panic(Input folder "&inpath" not found.);
  %end;
  %if %nrquote(&outlib) =                  %then %panic(Output libref not specified.);
  %if %qsysfunc(libref(&outlib))           %then %panic(Output libref %upcase(&outlib) not found.);
  %if %nrquote(&inlib) = %nrquote(&outlib) %then %panic(Identical librefs: Output datasets may not overwrite input datasets.);
  %if %nrquote(&inpath) = "%sysfunc(pathname(&outlib))"
                                           %then %panic(Identical paths: Output datasets may not overwrite input datasets.);
  %if %nrquote(&xptpath) ne %then %do;
    %repo_ws_exists(lsaf_path=&xptpath);
    %if &_repo_ws_exists_ = 0              %then %panic(XPT destination folder "&xptpath" not found.);
  %end;
  %if %nrquote(&inpath) ne %then
    %if %nrquote(&inpath) = %nrquote(&xptpath) %then %panic(Identical paths: XPT files may not overwrite input datasets.);
  %if %nrquote(&inlib) ne %then
    %if %qsysfunc(pathname(&inlib)) = %nrquote(&xptpath)
                                           %then %panic(Identical libref paths: XPT files may not overwrite input datasets.);
  %let sortdata = %upcase(%substr(%left(&sortdata), 1, 1));
  %let trimdata = %upcase(%substr(%left(&trimdata), 1, 1));
  %let emptydel = %upcase(%substr(%left(&emptydel), 1, 1));
  %if &sortdata = Y or &sortdata = N %then;%else %panic(%str(Parameter SORTDATA must be one of y, Y, Yes, YES, n, N, No, NO.));
  %if &trimdata = Y or &trimdata = N %then;%else %panic(%str(Parameter TRIMDATA must be one of y, Y, Yes, YES, n, N, No, NO.));
  %if &emptydel = Y or &emptydel = N %then;%else %panic(%str(Parameter EMPTYDEL must be one of y, Y, Yes, YES, n, N, No, NO.));
  %if %nrquote(&pgmpath) ne %then %do;
    %repo_ws_exists(lsaf_path=&pgmpath);
    %if &_repo_ws_exists_ = 0              %then %panic(Program folder "&pgmpath" not found.);
  %end;
  
  /* 3 simmilar pieces of code not to be an internal macro, as they create macro array variables */
  /* Get name, path, and number of input datasets, if any */
  %let innames = 0;
  %if %nrquote(&inpath) ne %then %do;
    %repo_ws_children(lsaf_path=&inpath, sas_dsname=_innames_, lsaf_recursive=1);
    proc sql noprint;
      select name,
             path
        into :inname1-,
             :innames1-
        from _innames_
       where isFolder = 0;
    quit;
    %let innames = &sqlobs;
  %end;

  /* Get name, path, and number of program to include, if any */
  %let pgmnames = 0;
  %if %nrquote(&pgmpath) ne %then %do;
    %repo_ws_children(lsaf_path=&pgmpath, sas_dsname=_pgmnames_, lsaf_recursive=1);
    proc sql noprint;
      select name,
             path
        into :pgmname1-,
             :pgmnames1-
        from _pgmnames_
       where isFolder = 0;
    quit;
    %let pgmnames = &sqlobs;
  %end;

  /* Get name, path, and number of XPT files to generate, if any */
  %let xptnames = 0;
  %if %nrquote(&xptpath) ne %then %do;
    %repo_ws_children(lsaf_path=&xptpath, sas_dsname=_xptnames_, lsaf_recursive=1);
    proc sql noprint;
      select name,
             path
        into :xptname1-,
             :xptnames1-
        from _xptnames_
       where isFolder = 0;
    quit;
    %let xptnames = &sqlobs;
  %end;

  /* Build sourcecode in a catalog entry to include later */
  %let catrefx = sasx%scan(%sysevalf(%sysfunc(ranuni(-1)) * 10000), 1, .);
  filename &catrefx catalog "work.code.&sysmacroname..source" lrecl=256;
  %if %nrquote(&debug) ne %then %do;
    %put NOTE: Created fileref &catrefx..;
  %end;

  /* Build a datastep for each dataset in metadata */
  /* If a program exists having the same name as the dataset, it is included BEFORE creation of the dataset */
  proc sort data=&metalib..&standard._datasets out=_datasets_;
    by comment dataset;
  run;

  data _null_;
    set _datasets_;
    by comment dataset;
    %if %nrquote(&dataset) ne %then
      where upcase(dataset) = upcase("&dataset");;
    file &catrefx;

    /* Common macro to validate if an input dataset exists */
    if _N_ = 1 then do;
      put '%macro dataset_test(dataset_test_dataset);';
      put '  %if %sysfunc(exist(&dataset_test_dataset)) = 0 %then %do;';
      put '    %if %sysfunc(libref(raw)) = 0 %then %sysfunc(libname(raw));';
      put '    %if %sysfunc(libref(xpt)) = 0 %then %sysfunc(libname(xpt));';
      put '    %panic(Program &pgmpath./&dataset_test_dataset..SAS did not produce dataset WORK.%upcase(&dataset_test_dataset).);';
      put '  %end;';
      put '%mend dataset_test;';
    end;

    /* Compose and execute a libname to RAW data, if any. Also generate code snippet for validation macro */
    inname = 0;
    do i = 1 to &innames;
      if upcase(symget(cats('inname', put(i, 3.)))) = upcase(cats(dataset, '.xpt')) then inname = i;
    end;
    if inname > 0 then do;
      inpath = symget(cats('innames', put(inname, 3.)));
      put "libname raw xport '&_SASWS_" inpath +(-1) "' access=readonly;";
      indata = cats(', indata=raw', '.', dataset);
    end;
    else if "&inlib" ne "" then do;
      if exist(cats("&inlib..", dataset)) then
        indata = cats(', indata=', "&inlib..", dataset);
    end;
  
    /* Libname to any XPT dataset to be generated. Also generate code snippet for data generation macro */
    if "&xptpath" ne "" then do;
      put "libname xpt xport '&_SASWS_.&xptpath./" %sysfunc(lowcase(dataset)) +(-1) ".xpt';";
      xptlib = ', xptlib=xpt';
    end;

    /* Include program having the same name as the dataset and call the macto to validate it's product in WORK */
    pgmname = 0;
    do i = 1 to &pgmnames;
      if upcase(symget(cats('pgmname', put(i, 3.)))) = upcase(cats(dataset, '.sas')) then pgmname = i;
    end;
    if pgmname > 0 then do;
      p_path = symget(cats('pgmnames', put(pgmname, 3.)));
      put "%include '&_SASWS_." p_path +(-1) "';";
      put '%dataset_test(' dataset +(-1) ');';
      pgmdata = cats(', indata=work.', dataset);
    end;
    else
      pgmdata = indata;

    /* Call the macro to generate one dataset */    
    put '%' "define_dataset(metalib=&metalib, standard=&standard, dataset=" dataset +(-1)
          pgmdata +(-1) ", outlib=&outlib, trimdata=&trimdata, sortdata=&sortdata, emptydel=&emptydel, debug=&debug" xptlib +(-1) ');';

    /* Free any datasets of files allocated earlier */
    if indata ne "" then
      put 'libname raw clear;';
    if xptlib ne "" then
      put 'libname xpt clear;';
  run;

  %include &catrefx;

  /* Clean up */
  %if %nrquote(&debug) = %then %do;
    filename &catrefx clear;
 
    proc datasets lib=work nolist;
      delete _innames_ _pgmnames_ _xptnames_ _datasets_;
    quit;
  %end;
  %else %do;
    %put NOTE: Remember to clean up fileref &catrefx..;

    data _null_;
      infile &catrefx dsd;
      input;
      if _N_ = 1 then put 'Generated code to generate all or selected dataset(s)';
      put _INFILE_;
    run;
  %end;
%mend define_datasets;
/*
Test statements:
libname metalib "C:\temp\metadata";
libname sdtm    "C:\sdtm";
%define_datasets(standard=sdtm, inpath=%str(C:\raw), outlib=sdtm, pgmpath=%str(C:\sdtm\programs));
libname adam    "C:\adam";
%define_datasets(standard=adam, dataset=adsl, inlib=sdtm, outlib=adam, emptydel=N, pgmpath=%str(C:\adam\programs));
*/