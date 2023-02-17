/***********************************************************************************************/
/* Description: Align define-xml metadata with CRF metadata by deleting non-essential parts of */
/*              define-xml which are not SDTM annotated in the CRF and adding additional SDTM  */
/*              annotations                                                                    */
/*              Basic TOC editing for ODS destinations are in effect                           */
/***********************************************************************************************/
/*  Copyright (c) 2021 Jørgen Mangor Iversen                                                   */
/*                                                                                             */
/*  Permission is hereby granted, free of charge, to any person obtaining a copy               */
/*  of this software and associated documentation files (the "Software"), to deal              */
/*  in the Software without restriction, including without limitation the rights               */
/*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell                  */
/*  copies of the Software, and to permit persons to whom the Software is                      */
/*  furnished to do so, subject to the following conditions:                                   */
/*                                                                                             */
/*  The above copyright notice and this permission notice shall be included in all             */
/*  copies or substantial portions of the Software.                                            */
/*                                                                                             */
/*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR                 */
/*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,                   */
/*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE                */
/*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER                     */
/*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,              */
/*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE              */
/*  SOFTWARE.                                                                                  */
/***********************************************************************************************/

%macro align_define_odm(metalib = metalib,  /* Metadata libref           */
                          debug = );        /* If any value, no clean up */
  %if %nrquote(&debug) ne %then %do;
    %put MACRO:   &sysmacroname;
    %put METALIB: &metalib;
  %end;

  %macro panic(msg); /* Message to be printed to the log before exiting */
    %if %nrquote(&msg) ne %then %put %str(ER)%str(ROR:) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if "&metalib" = "" %then %let metalib=metalib;
  %if %sysfunc(libref(&metalib)) %then %panic(Metadata libref %upcase(&metalib) not found.);

  proc sql;
    /* Non-essential datasets not in CRF annotations */
    %if %sysfunc(exist(&metalib..crf_datasets)) %then %do;
    create table _temp_datasets as select *
      from &metalib..sdtm_datasets a
     where class not = 'TRIAL DESIGN'
       and not exists (select *
                         from &metalib..crf_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_datasets a
     where exists (select *
                     from _temp_datasets b
                    where a.dataset = b.dataset);
    %end;

    /* Variables from deleted datasets*/
    create table _temp_dataset_vars as select *
      from &metalib..sdtm_variables a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_variables a
     where exists (select *
                     from _temp_dataset_vars b
                    where a.dataset = b.dataset);

    /* Non-essential variables not in the CRF annotations, keeping derived variables */
    %if %sysfunc(exist(&metalib..crf_variables)) %then %do;
    create table _temp_unused_vars as select *
      from &metalib..sdtm_variables a
     where mandatory = 'No'
       and origin   ne 'Derived'
       and not exists (select *
                         from &metalib..crf_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);
    delete from &metalib..sdtm_variables a
     where exists (select *
                     from _temp_unused_vars b
                    where a.dataset  = b.dataset
                      and a.variable = b.variable);
    %end;

    /* Value Level not referred by Datasets and Variables */
    create table _temp_valuelevel as select *
      from &metalib..sdtm_valuelevel a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);
    delete from &metalib..sdtm_valuelevel a
     where exists (select *
                     from _temp_valuelevel b
                    where a.dataset  = b.dataset
                      and a.variable = b.variable);

    /* Where Clauses from deleted Value Level */
    create table _temp_whereclauses as select *
      from sdtm_whereclauses a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);
    delete from &metalib..sdtm_whereclauses a
     where exists (select *
                     from _temp_whereclauses b
                    where a.dataset  = b.dataset
                      and a.variable = b.variable);

    /* Methods not referred by Variables and deleted Value Level */
    create table _temp_methods as select *
      from &metalib..sdtm_methods a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.id = b.method)
       and not exists (select *
                         from &metalib..sdtm_valuelevel c
                        where a.id = c.method);
    delete from &metalib..sdtm_methods a
     where exists (select *
                     from _temp_methods b
                    where a.id = b.id);

    /* Comments not referred by Datasets, Variables, Value Level */
    create table _temp_comments as select *
      from &metalib..sdtm_comments a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.id = b.comment)
       and  not exists (select *
                         from &metalib..sdtm_variables c
                        where a.id = c.comment)
       and  not exists (select *
                         from &metalib..sdtm_valuelevel d
                        where a.id = d.comment);
    delete from &metalib..sdtm_comments a
     where exists (select *
                     from _temp_comments b
                    where a.id = b.id);

    create table _temp_codelists as select *
      from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.id = b.codelist)
       and not exists (select *
                         from &metalib..sdtm_valuelevel c
                        where a.id = c.codelist);
    delete from &metalib..sdtm_codelists a
     where exists (select * 
                     from _temp_codelists b
                    where a.id = b.id);

    /* Extra code lists from the CRF annotations */
    create table _temp_extralists as select
           ID,
           Name,
           NCI_Codelist_Code,
           Data_Type,
           Order,
           Term,
           NCI_Term_Code,
           Decoded_Value length=200
      from &metalib..crf_codelists a
     where not exists (select *
                         from &metalib..sdtm_codelists b
                        where a.id = b.id)
                        ;
  quit;
  
  /* Two steps due to SQL restrictions AND define-xml version differences */
  proc append base=&metalib..sdtm_codelists data=_temp_extralists;
  run;


  /* Print one dataset to the ODS destination putting the title in the navigation menu */
  %macro odsprint(data=, title=);
    ods proclabel "&title";
    title         "&title";
    %let contents = %qsysfunc(propcase(%qsubstr(&data, 7)));
    proc print data=&data noobs label contents="&contents";
    run;
    title;
  %mend;

  %odsprint(data=_temp_datasets,     title=%str(Non-essential datasets not in CRF annotations));
  %odsprint(data=_temp_dataset_vars, title=%str(Variables from deleted datasets));
  %odsprint(data=_temp_unused_vars,  title=%str(Non-essential variables not in the CRF annotations, keeping derived variables));
  %odsprint(data=_temp_valuelevel,   title=%str(Value Level not referred by any Variables));
  %odsprint(data=_temp_whereclauses, title=%str(Where Clauses not referred by any Value Level));
  %odsprint(data=_temp_codelists,    title=%str(Code Lists and values not referred by any Variable or Value Level));
  %odsprint(data=_temp_extralists,   title=%str(Extra code lists from the CRF annotations));
  %odsprint(data=_temp_methods,      title=%str(Computational Methods not referred by any Variables or Value Level));
  %odsprint(data=_temp_comments,     title=%str(Comments not referred by any Dataset or Variables or Value Level));

  %if %sysfunc(exist(&metalib..crf_variables)) %then %do;
  proc sql;
    create table _temp_crf as select distinct
           dataset,
           variable,
           variable as crf label='CRF'
      from &metalib..crf_variables
     where dataset ne ''
     union select distinct
           dataset,
           crf_questions.SDSVarName as variable,
           crf_questions.SDSVarName as crf label='CRF'
      from &metalib..crf_questions
     inner join &metalib..crf_variables
        on crf_questions.SDSVarName = crf_variables.variable
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
    if crf ne sdtm;
  run;
  
  %odsprint(data=_temp_mismatch, title=%str(Mismatch between SDTM variables having origin=CRF and the CRF itself));
  %end;

  /* Clean-up */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _temp_:;
    quit;
  %end;
%mend;

/*
LSAF:
libname metalib "&_SASWS_./leo/clinical/lp9999/8888/metadata/data";
options nocenter;
ods listing close;
ods html file="&_SASWS_./leo/development/library/metadata/align_define_odm.html";
%align_define_odm;
ods html close;
ods listing;

SAS:
libname metalib "W:\XML Mapper\metalib";
ods listing close;
ooptions nocenter;
ds html file='align_define_odm.html';
%align_define_odm;
ods html close;
ods listing;
*/
