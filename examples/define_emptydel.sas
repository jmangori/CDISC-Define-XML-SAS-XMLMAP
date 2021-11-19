/***********************************************************************************/
/* Description: Remove all premissable variables witout contents                   */
/*              Preserve dataset and variable attributes                           */
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

%macro define_emptydel(metalib =metalib, /* metadata libref          */
                       standard=,        /* standard (sdtm/adam/crf) */
                       dataset =,        /* dataset to proccess      */
                       debug   =);       /* If any value, no clean up */
  %if %nrquote(&debug) ne %then %do;
    %put MACRO:    &sysmacroname;
    %put METALIB:  &metalib;
    %put STANDARD: &standard;
    %put DATASET:  &dataset;
  %end;

  /* Validate parameters and set up default values */
  %if "&metalib" = ""                        %then %let metalib = metalib;
  %if %qsysfunc(libref(&metalib))            %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if "&standard" = ""                       %then %panic(Standard not specified.);
  %if %sysfunc(exist(&metalib..&standard._datasets)) = 0
                                             %then %panic(Standard %sysfunc(lowcase(&standard)) not found.);
  %let standard = %scan(&standard, 1);       /* Discard version numbers etc. */
  %if %nrquote(&dataset) =                   %then %panic(Dataset &dataset not found.);
  %else %do;
    %if %index(&dataset, .) %then %do;
      %let lib = %qscan(&dataset, 1, .);
      %let mem = %qscan(&dataset, 2, .);
      %if %qsysfunc(libref(&lib))            %then %panic(Libref %qupcase(&lib) not found.);
    %end;
    %else %do;
      %let lib = WORK;
      %let mem = &dataset;
    %end;
    %let fileid = %qsysfunc(open(sashelp.vmember (where=(upcase(libname) = "%qupcase(&lib)" and upcase(memname) = "%qupcase(&mem)"))));
    %if &fileid = 0                          %then %panic(%qsysfunc(sysmsg()));
    %let found = %qsysfunc(fetch(&fileid));
    %let rc    = %qsysfunc(close(&fileid));
    %if &found                               %then %panic(Input data %qupcase(&lib..&mem) not found.);
  %end;
 
  %let emptydel=;
  %let datatype=;
  %let label=;

  proc sql noprint;
    select variable,
           data_type
      into :emptyvar1-,
           :datatype1-
      from &metalib..&standard._variables
      join dictionary.columns
        on upcase(libname) = upcase("&lib")
       and upcase(memname) = upcase(dataset)
       and upcase(name)    = upcase(variable)
     where upcase(dataset) = upcase("&mem")
       and mandatory = 'No';
    %let emptydels = &sqlobs;

    %let label=;
    select strip(memlabel) length=40
      into :label
      from dictionary.tables
     where upcase(libname) = upcase("&lib")
       and upcase(memname) = upcase("&mem");
   
    select name
      into :sortvar1-
      from dictionary.columns
     where upcase(libname) = upcase("&lib")
       and upcase(memname) = upcase("&mem")
       and sortedby ne 0
     order by sortedby;
    %let sortvars = &sqlobs;
  quit;

  /* If debugging requested, print macro arrays to the log */
  %if %nrquote(&debug) ne %then %do;
    %put &=emptydels;
    %put #  EMPTYVAR DATATYPE;
    %do i = 1 %to &emptydels;
      %put %qsysfunc(putn(&i, z2)) %sysfunc(putc(&&emptyvar&i, $8.)) %sysfunc(putc(&&datatype&i, $8.));
    %end;
    %put;
    %put DATASET &=label;
    %put;
    %put &=sortvars;
    %do i = 1 %to &sortvars;
      %put SORTVAR&i=&&sortvar&i;
    %end;
  %end;

  /* Stop if no variables to check for contents */
  %if &emptydels = 0 %then %return;

  /* Generate code to test if any variable is empty */
  filename emptydel catalog "work.code.&sysmacroname..source";

  data _null_;
    file emptydel;
    put "data _null_;";
    put "  set &dataset (keep=" @;
    do i = 1 to &emptydels;
      emptydel = symget(cats("emptyvar", put(i, 3.)));
      put emptydel @;
    end;
    put ") end=tail;";
    put "  array flags [&emptydels] _TEMPORARY_ (&emptydels * 0);";
    do i = 1 to &emptydels;
      emptydel = symget(cats("emptyvar", put(i, 3.)));
      datatype = symget(cats("datatype", put(i, 3.)));
      if datatype in ('text' 'date' 'datetime') then
        put "  if " emptydel " ne ' ' then flags[" i "] = 1;";
      else
        put "  if " emptydel " ne . then flags[" i "] = 1;";
    end;
    do i = 1 to &emptydels;
      macrovar = cats('emptydel', put(i, 3.));
      put "  if tail then call symput('" macrovar +(-1) "', strip(put(flags[" i +(-1) "], 3.)));";
    end;
    put "run;";
  run;

  %include emptydel;

  /* If debugging is requested, print the generated code to the log */
  %if %nrquote(&debug) ne %then %do;
    data _null_;
      infile emptydel dsd;
      input;
      if _N_ = 1 then put 'Generated code to test if any variable is empty';
      put _INFILE_;
    run;
  %end;

  /* Stop if no observations */
  %if %qsysfunc(symexist(emptydel1)) = 0 %then %return;

  /* If any sorting variables are dropped, remove them from the list of sorting variables */
  %let sortlist = ;
  %do i = 1 %to &sortvars;
    %let sortlist = %trim(&sortlist) &&sortvar&i;
    %do j = 1 %to &emptydels;
      %if &&sortvar&i = &&emptyvar&j and &&emptydel&j = 0 %then %do;
        %let sortlist = %substr(&sortlist, 1, %sysfunc(findc(&sortlist, %str( ), b)));
      %end;
    %end;
  %end;
  %if %nrquote(&debug) ne %then %put &=sortlist;
  %if &sortlist = %then %return;

  /* Sort the dataset in situ, dropping all empty variables */
  data _null_;
    call execute("proc sort data=&dataset (label='&label ' drop=");
    do i = 1 to &emptydels;
      if symget(cats('emptydel', put(i, 3.))) = '0' then
        call execute(symget(cats('emptyvar', put(i, 3.))));
    end;
    call execute(") force;by &sortlist;run;");
  run;

  /* Clean up */
  %if %nrquote(&debug) = %then %do;
    filename emptydel clear;
  %end;
  %else %put NOTE: Remember to clean up fileref EMPTYDEL.;
%mend define_emptydel;

/*
Test statements:
libname metalib "C:\temp\metadata";
libname adam    "C:\adam\data";
%define_datasets(standard=adam, dataset=adsl, inlib=sdtm, outlib=adam, emptydel=N, pgmpath=%str(C:\adam\programs));
%define_emptydel(metalib=metalib,standard=adam,dataset=adam.adsl);
*/