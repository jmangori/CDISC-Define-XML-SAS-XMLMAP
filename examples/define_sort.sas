/***********************************************************************************/
/* Description: Sort a dataset according to metadata taking into account that      */
/*              expected sort variables may have been deleted from the dataset     */
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

%macro define_sort(metalib =metalib, /* metadata libref           */
                   standard=,        /* standard (sdtm/adam)      */
                   dataset =,        /* dataset to sort           */
                   debug   =);       /* If any value, no clean up */
  %if %nrquote(&debug) ne %then %do;
    %put MACRO:    &sysmacroname;
    %put METALIB:  &metalib;
    %put STANDARD: &standard;
    %put DATASET:  &dataset;
  %end;

  /* Validate parameters and set up default values */
  %if %nrquote(&metalib) =                   %then %let metalib = metalib;
  %if %qsysfunc(libref(&metalib))            %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %nrquote(&standard) =                  %then %panic(Standard not specified.);
  %if %sysfunc(exist(&metalib..&standard._datasets)) = 0
                                             %then %panic(Standard %sysfunc(lowcase(&standard)) not found.);
  %let standard = %scan(&standard, 1);       /* Discard version numbers etc. */
  %if %nrquote(&dataset) =                   %then %panic(Dataset &dataset not found.);
  %else %do;
    %if %index(&dataset, .) %then %do;
      %let _sort_lib = %qscan(&dataset, 1, .);
      %let _sort_mem = %qscan(&dataset, 2, .);
      %if %qsysfunc(libref(&_sort_lib))      %then %panic(Libref %qupcase(&_sort_lib) not found.);
    %end;
    %else %do;
      %let _sort_lib = WORK;
      %let _sort_mem = &dataset;
    %end;
    %let _sort_fileid = %sysfunc(open(sashelp.vmember (where=(upcase(libname) = "%qupcase(&_sort_lib)" and upcase(memname) = "%qupcase(&_sort_mem)"))));
    %if &_sort_fileid = 0                    %then %panic(%qsysfunc(sysmsg()));
    %let _sort_found = %sysfunc(fetch(&_sort_fileid));
    %let _sort_rc    = %sysfunc(close(&_sort_fileid));
    %if &_sort_found                         %then %panic(Input data %qupcase(&_sort_lib..&_sort_mem) not found.);
  %end;

  %if %nrquote(&debug) ne %then %do;
    %put &=_sort_lib;
    %put &=_sort_mem;
  %end;

  /* Create an informat testing for existence while preserving variable order */
  data _define_sort_fmt;
    set &metalib..&standard._datasets;
    where upcase(dataset) = "%upcase(&_sort_mem)";
    fmtname = 'sortvar';
    type    = 'i';
    do label = 1 to countw(Key_Variables, ',');
      start = upcase(scan(Key_Variables, label, ','));
      output;
    end;
    keep fmtname type start label;
  run;

  proc format cntlin=_define_sort_fmt;
  run;

  /* Test expected sort variables for existense in the actual dataset */
  %let _sort_keys =;
  proc sql noprint;
    select distinct
           name,
           input(upcase(name), sortvar.) as sort_order
      into :_sort_keys separated by ' ',
           :_sort_dummy 
      from dictionary.columns
     where upcase(libname) = "%upcase(&_sort_lib)"
       and upcase(memname) = "%upcase(&_sort_mem)"
       and input(upcase(name), sortvar.) ne .
     order by sort_order;
  quit;

  %if %nrquote(&debug) ne %then %do;
    %put &=_sort_keys;
  %end;

  /* Sort the actual dataset by key variables in the expected order */
  %if &_sort_keys ne %then %do;
    proc sort data=&dataset force;
      by &_sort_keys;
    run;
  %end;

  /* Clean up */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _define_sort_:;
    quit;
  %end;
%mend define_sort;

/*
Test statements:
libname metalib "C:\temp\metadata";
libname sdtm    "C:\sdtm\data";
%define_sort(standard=sdtm, dataset=sdtm.ae, debug=y);
*/