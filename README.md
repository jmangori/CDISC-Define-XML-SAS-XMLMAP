# Table of Contents
* [About The Project](#About_The_Project)
  * [Built With](#Built_With)
  * [Versions covered](#Versions_covered)
* [Getting Started](#Getting_Started)
  * [Prerequisites](#Prerequisites)
  * [Installation](#Installation)
* [Usage](#Usage)
  * [define_2_0_0.map](#define_2_0_0_map)
  * [odm_1_3_2.map](#odm_1_3_2_map)
  * [define_2_0_0.sas](#define_2_0_0_sas)
  * [odm_1_3_2.sas](#odm_1_3_2_sas)
  * [define_crf.sas](#define_crf_sas)
* [Roadmap](#Roadmap)
* [License](#License)
* [Contact](#Contact)
* [Acknowledgements](#Acknowledgements)

# About The Project <a name="About_The_Project"/>
For one and a half decade I have sought high and low for a (set of) SAS XMLMAP(s) to convert CDISC ODM-xml and define-xml files into SAS datasets for building metadata driven processes to report and analyze clinical trials. After way too much patience I decided to build them myself.

![Infographic about mapping](./images/mapping_overview.png)

The define-xml can serve as a one source of truth for the definition of SDTM and ADaM data specifications. Define-xml was originally developed as a documentation tool, but by feeding the dog it’s own tail, it can do much more than this acting as a definition document. The idea is to have a specification document to allow SDTM and ADaM datasets to be built in an automated way. SAS being the (still) preferred analysis tool in the pharma industry, such automation calls for a conversion of the metadata within define-xml to be converted to SAS datasets. Furthermore, the define-xml itself as a specification can be handed over to any external data provider (CRO) as a definition of expected deliverables. Once the data is delivered, a new define-xml can be produced from the data package using any available tool to do so, and the resulting define-xml can the be compared to the specification one, to measure any gaps between the specification and the delivery. Such a XML comparison tool is not part of this project.

## Built With <a name="Built_With"/>
The SAS XMLMAPS for converting any CDISC ODM-xml file and CDISC define-xml files into SAS datasets is build using the freely available SAS XML Mapper tool in its original configuration as it comes as a download from SAS Institute. No tweaking or java upgrades were performed. The SAS XML Mapper is available from SAS Institute at [SAS Downloads: SAS XML Mapper](https://support.sas.com/downloads/package.htm?pid=486). You will need to register at the SAS web page to get the download. This tool creates an XML document in a particular format for defining SAS datasets from an example XML source file and an optional XML schema file. The main engine in the process is the XPATH language as known from other contexts.

## Versions covered <a name="Versions_covered"/>
* Define-xml version 2.0.0
* ODM-xml version 1.3.2
* SAS version 9.2 and above.

# Getting Started <a name="Getting_Started"/>
Download the documents and place them at the location where they are needed.

## Prerequisites <a name="Prerequisites"/>
SAS/Base software minimum version 9.2. If you are running in a SAS 9.2 session, use the alias XML92 as the XML engine name in place of XMLV2.

## Installation <a name="Installation"/>
The XMLMAP files can reside anywhere on your computer or system. The only requirement is that they are available to the SAS program that wants to use them. Then write a SAS program along these lines:

```sas
filename define “<your drive>:\<your path>\<your define file.xml>”;
filename xmlmap “<your drive>:\<your path>\define_2_0_0.map”;
libname  define xmlv2 xmlmap=xmlmap access=READONLY compat=yes;
```

Please pay attention to the specific options to the `libname` statement. Please note that the **fileref** for the XML file must be identical to **libref** of the `libname` statement as per the SAS documentation of the XML (and XMLV2) engines of the `libname` statement.

These three statements creates a **libref** to the XML document enabling SAS to read all datasets defined in the XMLMAP as SAS datasets.

# Usage <a name="Usage"/>
## define_2_0_0.map <a name="define_2_0_0_map"/>
This document is a piece of XML defining how to interpret a valid CDSIC define-xml file as a set of SAS datasets defining metadata for a clinical trial. Both SDTM and ADaM is supported. The resulting datasets can be used to easily implement a datamodel widely used for clinical trial metadata.

Example program:

```sas
filename define “W:\XML Mapper\SDTM Define-XML 2.0.xml”;
filename xmlmap “W:\XML Mapper\define_2_0_0.map”;
libname  define xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

proc copy in=define out=work;
run;
```

The result is a copy of all the datasets defined in the `define_2_0_0.map` file, which has an XPATH representation within the define-xml file. These files can be used for further processing in SAS to build the complete metadata for a collection of SDTM or ADaM datasets, depenent of the contents of the define-xml file.

![Example dataset from define-xml](./images/DefineDatasets.png)

## odm_1_3_2.map <a name="odm_1_3_2_map"/>
This document is a piece of XML defining how to interpret a valid CDISC ODM-xml file as a set of SAS datasets defining metadata for a clinical trial. The resulting datasets can be used to display an SDTM annotated CRF, as well as pruning SDTM metadata to comply with a corresponding CRF.

Example program:

```sas
filename odm “W:\XML Mapper\CDISC odm 1.3.2.xml”;
filename map “W:\XML Mapper\odm_1_3_2.map”;
libname  odm xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

proc copy in=odm out=work;
run;
```

The result is a copy of all the datasets defined in the `odm_1_3_2.map` file, which has an XPATH representation within the ODM-xml file. These files can be used for further processing in SAS to build a rendition of the CRF, of coorelating the contents of define-xml and ODM_xml.

![Example dataset from odm-xml](./images/ODMDatasets.png)

## define_2_0_0.sas <a name="define_2_0_0_sas"/>
This program is a SAS macro to incapsulate all the details of the mapping and subsequent construction of a very familliar data model as SAS datasets. The data model consists of dataset to hold the familliar levels of metadata that comprises a define-xml document.

Example program:

```sas
libname metalib "C:\temp\metadata";
%define_2_0_0(define = %str(C:\temp\metadata\SDTM Define-XML 2.0.xml),
             xmlmap  = %str(C:\temp\metadata\define_2_0_0.map));
%define_2_0_0(define = %str(C:\temp\metadata\ADaM Define-XML 2.0.xml),
             xmlmap  = %str(C:\temp\metadata\define_2_0_0.map));
```

The result is a collection of SAS datasets per CDISC data model (SDTM/ADaM) organized the same way. These files can be used for a standardized way (macros etc.) to generate CDISC compliant SAS datasets, dependent on the correctness of the define-xml input file.

![Example dataset define_2__0_0.sas](./images/MetadataDatasets.png)

## odm_1_3_2.sas <a name="odm_1_3_2_sas"/>
This program is a SAS macro to create a set of SAS datasets following exactly the same data struture as the `%define_2_0_0.sas` macro, enabling the CRF to be compared to the SDTM define-xml for the same study.

## define_crf.sas <a name="define_crf_sas"/>
This program is a SAS macro to adjust the metadata tables created via the `define_2_0_0.sas` macro, with the intent to align a specification define-xml to the SDTM annotations within an ODM-xml file, serving as a specification of a corresponding CRF. This is only valid for a define-xml specification of SDTM, not ADaM.

All changes are printed to the standard SAS output destinations, as well as a report of all define-xml variables having **Origin='CRF'** versus all variables in the SDTM annotations of the CRF. This last report is intended to catch missalignments between the **Origin** column in the define-xml specification and the SDTM annotations of the CRF specification.

# Roadmap <a name="Roadmap"/>
As new version of ODM-xml and define-xml are published by CDISC, I hope to be able to write new versions of relevant documents for these.

I am considering to write XSL Translating Style Sheets to replace the XML maps, to be able to include more business logic for creating a more coherent data model. This may not require another XML Map, as the target could be one of the simple data models built into the XMLV2 engine.

# License <a name="License"/>
Distributed under the MIT License. See [LICENSE](https://github.com/jmangori/CDISC-ODM-and-Define-XML-tools/blob/master/LICENSE) for more information.

# Contact <a name="Contact"/>
Jørgen Mangor Iversen [jmi@try2.info](mailto:jmi@try2.info)

[My web page in danish](http://www.try2.info) unrelated to this project.

[My LinkedIn profile](https://www.linkedin.com/in/jørgen-iversen-ab5908b/)

# Acknowledgements <a name="Acknowledgements"/>
This software is made public with the explicit permission from LEO Pharma A/S
