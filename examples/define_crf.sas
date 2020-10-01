/***********************************************************************************/
/* Study:        Standard program                                                  */
/* Program Name: define_crf.sas                                                    */
/* Description:  Align define-xml metadata with CRF metadata by deleting           */
/*               parts of define-xml which are not SDTM annotated in the CRF and   */
/*               adding additional SDTM annotations (extra codelists)              */
/*               Changes are printed, as well as missmatches in define-xml origins */
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

%macro define_crf(metalib = metalib); /* metadata libref */
  %put MACRO:   &sysmacroname;
  %put METALIB: &metalib;

  /* Print a message to the log and terminate macro execution */
  %macro panic(msg);
    %put %sysfunc(cats(ER, ROR:)) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if "&metalib" = "" %then %let metalib=metalib;
  %if %sysfunc(libref(&metalib)) %then %panic(Metadata libref %upcase(&metalib) not found.);

  proc sql;
    /* Non-essential datasets not in CRF annotations */
    create table _temp_datasets as select *
      from &metalib..sdtm_datasets a
     where class not = 'TRIAL DESIGN'
       and not exists (select *
                         from &metalib..crf_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_datasets a
     where class not = 'TRIAL DESIGN'
       and not exists (select *
                         from &metalib..crf_datasets b
                        where a.dataset = b.dataset);

    /* Variables from deleted datasets*/
    create table _temp_variables as select *
      from &metalib..sdtm_variables a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_variables a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.dataset = b.dataset);

    /* Non-essential variables not in the CRF annotations, keeping derived variables */
    create table _temp_extravars as select *
      from &metalib..sdtm_variables a
     where mandatory = 'No'
       and origin   ne 'Derived'
       and not exists (select *
                         from &metalib..crf_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);
    delete from &metalib..sdtm_variables a
     where mandatory = 'No'
       and origin   ne 'Derived'
       and not exists (select *
                         from &metalib..crf_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);

    /* Code lists from deleted variables */
    create table _temp_codelists as select *
      from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.name = b.codelist);
    delete from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.name = b.codelist);

    /* Code list values not in the CRF annotations */
    create table _temp_codevalues as select *
      from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..crf_codelists b
                        where a.NCI_Codelist_Code = b.NCI_Codelist_Code
                          and a.NCI_Term_Code     = b.NCI_Term_Code);
    delete from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..crf_codelists b
                        where a.NCI_Codelist_Code = b.NCI_Codelist_Code
                          and a.NCI_Term_Code     = b.NCI_Term_Code);

    /* Extra code lists from the CRF annotations */
    create table _temp_extralists as select *
      from &metalib..crf_codelists a
     where not exists (select *
                         from &metalib..sdtm_codelists b
                        where a.name = b.name);

    /* Two steps due to SQL restrictions */
    insert into &metalib..sdtm_codelists
    select *
      from _temp_extralists;
  quit;

  title "Non-essential datasets not in CRF annotations";
  proc print data=_temp_datasets noobs label;
  run;

  title "Variables from deleted datasets";
  proc print data=_temp_variables noobs label;
  run;

  title "Non-essential variables not in the CRF annotations, keeping derived variables";
  proc print data=_temp_extravars noobs label;
  run;

  title "Code lists from deleted variables";
  proc print data=_temp_codelists noobs label;
  run;

  title "Code list values not in the CRF annotations";
  proc print data=_temp_codevalues noobs label;
  run;

  title "Extra code lists from the CRF annotations";
  proc print data=_temp_extralists noobs label;
  run;

  proc sql;
    create table _temp_crf as select distinct
           dataset,
           variable,
           variable as crf label='CRF'
      from &metalib..crf_variables
     where dataset ne ''
     order by dataset, variable;

    create table _temp_sdtm as select distinct
           dataset,
           variable,
           variable as sdtm label='SDTM'
      from &metalib..sdtm_variables
     where upcase(origin)='CRF'
     order by dataset, variable;
   quit;

  data _temp_mismatch (drop=variable);
    merge _temp_crf _temp_sdtm;
    by dataset variable;
  run;

  title "Mismatch between SDTM variables having origin=CRF and the CRF itself";
  proc print data=_temp_mismatch noobs label;
    where crf ne sdtm;
    by dataset;
  run;

  /* Clean-up */
  proc datasets lib=work nolist;
    delete _temp_:;
  quit;
%mend;

/*
Test statements:
libname metalib "C:\temp\metadata";
%define_crf;
*/
