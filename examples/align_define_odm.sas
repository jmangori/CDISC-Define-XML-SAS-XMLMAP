/***********************************************************************************************/
/* Description: Align define-xml metadata with CRF metadata by deleting non-essential parts of */
/*              define-xml which are not SDTM annotated in the CRF and adding additional SDTM  */
/*              annotations                                                                    */
/*              Basic TOC editing for ODS destinations are in effect                           */
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

  /* Extract Value Level from Question Alias */
  proc sort data=crf_questions (keep=SDSVarName Context Alias CodeListOID Question) out=_temp_align_questions (drop=Context);
    by    SDSVarName;
    where Context = 'SDTM' and Alias ? 'QNAM';
  run;

  data _temp_align_qnamlab;
    set    _temp_align_questions;
    by     SDSVarName;
    length Mandatory $ 200;
    rename CodeListOID = Codelist;
    retain Order 0;
    if first.SDSVarName then Order = 0;
    if indexw(upcase(substr(Question, 1, 3)), 'IF') then Mandatory = 'No'; else Mandatory = 'Yes';
    do qi = 1 to count(Alias, 'QNAM');
      qnamp = index(Alias, '.QNAM=')   - 6;
      qlabp = index(Alias, '.QLABEL=') + 9;
      qsupp = substr(Alias, qnamp, 6);
      qnam = scan(substr(Alias, qnamp + 12), 1);
      qlab = substr(Alias, qlabp, findc(Alias, "'", qlabp + 2) - qlabp);
      Alias = substr(Alias, qnamp);
      Order = Order + 1;
      output;
    end;
    drop Question Alias qnamp qlabp qi;
  run;

  proc sort data=_temp_align_qnamlab nodupkey;
    by SDSVarName qnam;
  run;

  proc sql;
    /* Non-essential datasets not in CRF annotations */
    %if %sysfunc(exist(&metalib..crf_datasets)) %then %do;
    create table _temp_align_datasets as select *
      from &metalib..sdtm_datasets a
     where class not = 'TRIAL DESIGN'
       and not exists (select *
                         from &metalib..crf_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_datasets a
     where exists (select *
                     from _temp_align_datasets b
                    where a.dataset = b.dataset);
    %end;

    /* Variables from deleted datasets*/
    create table _temp_align_dataset_vars as select *
      from &metalib..sdtm_variables a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.dataset = b.dataset);
    delete from &metalib..sdtm_variables a
     where exists (select *
                     from _temp_align_dataset_vars b
                    where a.dataset = b.dataset);

    /* Non-essential variables not in the CRF annotations, keeping derived variables */
    %if %sysfunc(exist(&metalib..crf_variables)) %then %do;
    create table _temp_align_unused_vars as select *
      from &metalib..sdtm_variables a
     where mandatory = 'No'
       and origin    = 'CRF' 
       and substr(dataset, 1, 4) not in ('POOL' 'RELR' 'RELS' 'SUPP')
       and not exists (select *
                         from &metalib..crf_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable);
    delete from &metalib..sdtm_variables a
     where exists (select *
                     from _temp_align_unused_vars b
                    where a.dataset  = b.dataset
                      and a.variable = b.variable);
    %end;

    /* Value Level not referred by Datasets and Variables */
    create table _temp_align_valuelevel_var as select *
      from &metalib..sdtm_valuelevel a
     where not exists (select distinct
                              dataset,
                              variable
                         from &metalib..sdtm_variables b
                        where a.dataset  = b.dataset
                          and a.variable = b.variable
                 union select distinct
                              qsupp as dataset  length=200,
                              qnam  as variable length=200
                         from _temp_align_qnamlab c
                        where a.dataset = qsupp
                          and scan(ItemOID, 3) = qnam);
    delete from &metalib..sdtm_valuelevel a
     where exists (select *
                     from _temp_align_valuelevel_var b
                    where a.itemoid = b.itemoid);

    /* Where Clauses from deleted Value Level */
    create table _temp_align_whereclauses as select *
      from &metalib..sdtm_whereclauses a
     where not exists (select *
                         from &metalib..sdtm_valuelevel b
                        where where_clause = id)
        or not exists (select *
                         from &metalib..sdtm_variables c
                        where a.dataset  = c.dataset
                          and a.variable = c.variable);
    delete from &metalib..sdtm_whereclauses a
     where exists (select *
                     from _temp_align_whereclauses b
                    where a.id  = b.id);

    /* More values not referred by where clauses */
    create table _temp_align_valuelevel_where as select *
      from &metalib..sdtm_valuelevel a
     where not exists (select distinct *
                         from &metalib..sdtm_whereclauses b
                        where where_clause = id);
    delete from &metalib..sdtm_valuelevel a
     where exists (select *
                     from _temp_align_valuelevel_where b
                    where a.itemoid = b.itemoid);

    /* Methods not referred by Variables and deleted Value Level */
    create table _temp_align_methods as select *
      from &metalib..sdtm_methods a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.id = b.method)
       and not exists (select *
                         from &metalib..sdtm_valuelevel c
                        where a.id = c.method);
    delete from &metalib..sdtm_methods a
     where exists (select *
                     from _temp_align_methods b
                    where a.id = b.id);

    create table _temp_align_codelists as select *
      from &metalib..sdtm_codelists a
     where not exists (select *
                         from &metalib..sdtm_variables b
                        where a.id = b.codelist)
       and not exists (select *
                         from &metalib..sdtm_valuelevel c
                        where a.id = c.codelist);
    delete from &metalib..sdtm_codelists a
     where exists (select * 
                     from _temp_align_codelists b
                    where a.id = b.id);

    /* Extra Code Lists from the CRF annotations */
    create table _temp_align_extralists as select
           ID,
           Name,
           NCI_Codelist_Code,
           Data_Type,
           Order,
           Term,
           NCI_Term_Code,
           'Yes' as ExtendedValue length=200,
           Decoded_Value length=200
      from &metalib..crf_codelists a
     where not exists (select *
                         from &metalib..sdtm_codelists b
                        where a.id = b.id)
                        ;
  quit;

  /* Two sets of Value level */
  data _temp_align_valuelevel;
    set _temp_align_valuelevel_var
        _temp_align_valuelevel_where;
  run;

  /* Extra Values from the CRF annotations */
  proc sql;
    create table _temp_align_extra_values_order as select distinct
           case when substr(SDSVarName, 1, 4) = 'SUPP' then
           cats('VL.', scan(SDSVarName, 1, '.'), '.QVAL')
           else cats('VL.SUPP', scan(SDSVarName, 1, '.'), '.QVAL') end as OID length=200,
           case when substr(SDSVarName, 1, 4) = 'SUPP' then
                catx('.', SDSVarName, qnam)
           else catx('.', qsupp, 'QVAL', qnam) end as ItemOID length=200,
           Order,
           case when substr(SDSVarName, 1, 4) = 'SUPP' then
                qsupp
           else cats('SUPP', scan(SDSVarName, 1))
           end as Dataset length=200,
           case when substr(SDSVarName, 1, 4) = 'SUPP' then
                scan(SDSVarName, 2)
           else 'QVAL' end as Variable length=200,
           case when substr(SDSVarName, 1, 4) = 'SUPP' then
                cats('WC.SQ', SDSVarName, '.', qnam, '.', '8888')
           else cats('WC.SQSUPP', scan(SDSVarName, 1), '.QVAL.', qnam, '.', '9999') end as Where_Clause length=200,
           qlab   as Description length=200,
           'text' as Data_Type   length=200,
           200    as Length,
           .      as Significant_Digits,
           ''     as Format      length=200,
           Mandatory,
           Codelist,
           'CRF'  as Origin      length=200,
           qnam   as Pages       length=500,
           ''     as Method      length=200,
           ''     as Predecessor length=200,
           ''     as Comment     length=200
      from _temp_align_qnamlab
     where not exists (select *
                         from &metalib..sdtm_valuelevel b
                        where scan(ItemOID, 3) = qnam)
     order by ItemOID;
  quit;

  data _temp_align_extra_values (drop=_:);
    set _temp_align_extra_values_order;
    retain _maxorder 0;
    if order ne 7777 then _maxorder = order;
    if _order = 7777 then order = _maxorder + 1;
  run;

  /* Extra Where Caluses from the extra Value Level */
  proc sql;
    create table _temp_align_extra_whereclauses as select
           Where_Clause as ID,
           Order,
           Dataset,
           Variable,
           'NE'     as Comparator length=200,
           ''       as Value      length=200,
           count(*) as Cardinality
      from _temp_align_extra_values
     group by Dataset,
           Variable,
           Comparator;

    /* Comments not referred by Datasets, Variables, Value Level */
    create table _temp_align_comments as select *
      from &metalib..sdtm_comments a
     where not exists (select *
                         from &metalib..sdtm_datasets b
                        where a.id = b.comment)
       and  not exists (select *
                         from &metalib..sdtm_variables c
                        where a.id = c.comment)
       and  not exists (select *
                         from &metalib..sdtm_valuelevel d
                        where a.id = d.comment)
       and  not exists (select *
                         from &metalib.._temp_align_extra_values e
                        where a.id = e.comment);
    delete from &metalib..sdtm_comments a
     where exists (select *
                     from _temp_align_comments b
                    where a.id = b.id);
  quit;

  /* Extra items are two steps due to SQL restrictions AND define-xml version differences */
  proc append base=&metalib..sdtm_codelists data=_temp_align_extralists;
  run;
  proc append base=&metalib..sdtm_whereclauses data=_temp_align_extra_whereclauses;
  run;

  /* Fix Order column for extra values after append */
  proc sort data=&metalib..sdtm_valuelevel;
    by Dataset Variable Order;
  run;

  proc sort data=_temp_align_extra_values;
    by Dataset Variable Order;
  run;

  data &metalib..sdtm_valuelevel (drop=_:);
    set &metalib..sdtm_valuelevel _temp_align_extra_values;
    by Dataset Variable;
    retain _order 0;
    if first.dataset or first.variable then _order = 1;
    Order = _order;
    _order = _order + 1;
  run;

  /* Print one dataset to the ODS destination putting the title in the navigation menu */
  %macro odsprint(data=, title=);
    proc sql noprint;
      select count(*) into :obs trimmed from &data.;
    quit;
    ods proclabel "&title (&obs.)";
    title         "&title (&obs.)";
    %let contents = %qsysfunc(propcase(%qsubstr(&data, 13)));
    proc print data=&data noobs label contents="&contents";
    run;
    title;
  %mend;

  %odsprint(data=_temp_align_datasets,           title=%str(Non-essential datasets not in CRF annotations));
  %odsprint(data=_temp_align_dataset_vars,       title=%str(Variables from deleted datasets));
  %odsprint(data=_temp_align_unused_vars,        title=%str(Non-essential variables not in the CRF annotations, keeping derived variables));
  %odsprint(data=_temp_align_valuelevel,         title=%str(Value Level not referred by any Variables));
  %odsprint(data=_temp_align_extra_values,       title=%str(Extra Value Levels from the CRF annotations));
  %odsprint(data=_temp_align_whereclauses,       title=%str(Where Clauses not referred by any Value Level));
  %odsprint(data=_temp_align_extra_whereclauses, title=%str(Extra Where Clauses from the CRF annotations));
  %odsprint(data=_temp_align_codelists,          title=%str(Code Lists and values not referred by any Variable or Value Level));
  %odsprint(data=_temp_align_extralists,         title=%str(Extra code lists from the CRF annotations));
  %odsprint(data=_temp_align_methods,            title=%str(Computational Methods not referred by any Variables or Value Level));
  %odsprint(data=_temp_align_comments,           title=%str(Comments not referred by any Dataset or Variables or Value Level));

  %if %sysfunc(exist(&metalib..crf_variables)) %then %do;
  proc sql;
    create table _temp_align_crf as select distinct
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

    create table _temp_align_sdtm as select distinct
           dataset,
           variable,
           variable as sdtm label='SDTM'
      from &metalib..sdtm_variables
     where upcase(origin)='CRF'
     order by dataset, variable;
   quit;

  data _temp_align_mismatch (drop=variable);
    merge _temp_align_crf _temp_align_sdtm;
    by dataset variable;
    if crf ne sdtm;
  run;

  %let move_origin = 0;
  proc sql noprint;
    select distinct count(*)
      into :move_origin trimmed
      from _temp_align_mismatch
     where crf ne ''
       and sdtm = '';

  %if &move_origin ne '' %then %do;
    update &metalib..sdtm_variables a
       set Origin      = 'CRF',
           Predecessor = '',
           Pages       = variable
     where exists (select *
                     from _temp_align_mismatch b
                    where a.dataset = b.dataset
                      and variable  = crf
                      and crf ne ''
                      and sdtm = '');
  %end;
  quit;

  footnote "Variables mentioned on the CRF but with SDTM origin as something else, have Origin changed into CRF, including Page Refs";
  %odsprint(data=_temp_align_mismatch, title=%str(Mismatch between SDTM variables having origin=CRF and the CRF itself));
  %end;
  footnote;

  /* Clean-up */
  %if %nrquote(&debug) = %then %do;
    proc datasets lib=work nolist;
      delete _temp_align_:;
    quit;
  %end;
%mend;

/*
libname metalib "X:\Users\jmi\metadata";
%let study = My study;

%odm_1_3_2(odm = %str(X:\Users\jmi\metadata\&study CRF Version 2 Draft.xml),
        xmlmap = %str(X:\Users\jmi\metadata\odm_1_3_2.map));

%define_2_0_0(define = %str(X:\Users\jmi\metadata\Global Standard SDTM Define-XML 2.0.xml),
             xmlmap  = %str(X:\Users\jmi\metadata\define_2_0_0.map));

ods listing close;
ods html body="X:\Users\jmi\metadata\data/&study._t.htm"                (url="&study._t.htm")
     contents="X:\Users\jmi\metadata\data\&study._menu.htm"             (url="&study._menu.htm")
        frame="X:\Users\jmi\metadata\data\&study._align_define_odm.htm" (title="Align CRF and Define for &study")
      newfile=page;

%align_define_odm;

ods html close;
ods listing;

%define_xml_2_0_0(define = %str(X:\Users\jmi\metadata\sdtm\&study._define.xml),
                standard = SDTM,
                 FileOID = define_&study.,
            SourceSystem = define_xml_2_0_0,
                StudyOID = SDY_&study.,
      MetaDataVersionOID = AG_&study.);

*/

