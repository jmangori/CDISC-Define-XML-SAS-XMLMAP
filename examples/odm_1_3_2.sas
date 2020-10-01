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
                  xmlmap = %str(odm_1_3_2.map)); /* XML Map with full path */
  %put MACRO:   &sysmacroname;
  %put METALIB: &metalib;
  %put ODM:     &odm;
  %put XMLMAP:  &xmlmap;

  /* Print a message to the log and terminate macro execution */
  %macro panic(msg);
    %put %sysfunc(cats(ER, ROR:)) &msg;
    %abort cancel;
  %mend panic;

  /* Validate parameters and set up default values */
  %if "&metalib" = "" %then %let metalib=metalib;
  %if "&odm"     = "" %then %panic(No odm-xml file specified in parameter ODM=.);
  %if "&xmlmap"  = "" %then %panic(No XML Map file specified in the parameter XMLMAP=.);
  %if %sysfunc(libref(&metalib))         %then %panic(Metadata libref %upcase(&metalib) not found.);
  %if %sysfunc(fileexist("&odm"))    = 0 %then %panic(ODM-xml file "&odm" not found.);
  %if %sysfunc(fileexist("&xmlmap")) = 0 %then %panic(XMLMAP file "&xmlmap" not found.);

  /* filename and libname are linked via the shared fileref/libref */
  filename odm    "&odm";
  filename xmlmap "&xmlmap" encoding="utf-8";
  libname  odm    xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

  /* Standard is always CRF in ODM-XML files */
  %let standard = crf;

  /* Build metadata tables inspired by P21 template */
  proc sql;
    /* Global metadata regarding one CRF snapshot and SDTM annotations */
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
           mdv.ProtocolDescription,
           mdv.IncludeMetaDataVersionOID,
           "&standard"    as StandardName,
           odm.ODMVersion as StandardVersion
      from odm.odm
      join odm.Study
        on odm.ID = STudy.ID
      join odm.Metadataversion mdv
        on Study.OID = mdv.StudyOID;

    /* Global definitions of measurement units */
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

    /* Very simple list of datasets from annotations */
    create table &metalib..&standard._datasets as select distinct
           Domain as Dataset
      from odm.Itemgroupdef
     order by Dataset;

    /* Itemgroupdefitemref contains relationships between datasets and variables */
    create table &metalib..&standard._Variables (drop=OrderNumber) as select distinct
           dsn.Domain        as Dataset,
           var.SDSVarName    as Variable,
           OrderNumber,
           CodeListOID,
           MethodOID,
           RoleCodeListOID,
           CollectionExceptionConditionOID,
           var.Comment
      from odm.Itemgroupdefitemref rel
      join odm.Itemgroupdef        dsn
        on rel.OID = dsn.OID
      join odm.Itemdef             var
        on rel.ItemOID = var.OID
     where Variable ne ''
     order by Dataset,
           OrderNumber;

    /* P21 has codes and enumerated items combined */
    create table &metalib..&standard._Codelists as select distinct
           cdl.OID                                    as ID,
           cdl.Name,
           cdl.Alias                                  as NCI_Codelist_Code,
           cdl.DataType                               as Data_Type,
           coalesce(itm.OrderNumber, enu.OrderNumber) as Order,
           coalescec(itm.CodedValue, enu.CodedValue)  as Term,
           coalescec(itm.Alias, enu.Alias)            as NCI_Term_Code,
           itm.Decode                                 as Decoded_Value
      from odm.CodeList                    cdl
      left join odm.CodeListItem           itm
        on itm.OID = cdl.OID
      left join odm.CodeListEnumeratedItem enu
        on enu.OID = cdl.OID
     order by ID,
           Term;

    /* Straight forward */
    create table &metalib..&standard._Dictionaries as select distinct
           OID as ID,
           Name,
           DataType as Data_Type,
           Dictionary,
           Version
      from odm.Codelist
     where Dictionary ne ''
     order by ID;

    /* Forms */
    create table &metalib..&standard._Forms as select distinct
           fmd.MDVOID,
           fmd.OID,
           fmd.Name as Form,
           Repeating,
           Description as FormDescription,
           fda.Context,
           fda.Name as FormAlias,
           fal.PdfFileName,
           fal.PresentationOID
      from odm.FormDef                   fmd
      left join odm.FormDefAlias         fda
        on fmd.MDVOID = fda.MDVOID
       and fmd.OID    = fda.OID
      left join odm.FormDefArchiveLayout fal
        on fmd.MDVOID = fal.MDVOID
       and fmd.OID    = fal.OID
     order by fmd.MDVOID, fmd.OID;

    /* Questions are mixed with SDTM variables in ItemDef */
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
           Description,
           Question,
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
     order by fgr.OID, ItemGroupOID, ItemOID;
  quit;
%mend;

/*
Test statements:
libname metalib "C:\temp\metadata";
%odm_1_3_2(odm = %str(C:\temp\metadata\CDISC ODM 1.3.2.xml),
        xmlmap = %str(C:\temp\metadata\odm_1_3_2.map));

proc copy in=odm out=work;run;
*/
