*************************************************************************************************************************;
* Project           : CDISC-ODM-and-Define-XML-tools
* Program name      : read_defines.sas
* Author            : Katja Glass
* Date created      : 2020-09-11
* Purpose           : Show how to apply the open source tool to transfer define.xml to SAS datasets
*
* Revision History  :
* Date				: 2020-08-31
* Author      		: Katja Glass 
* Description       : Only minor modification to comment code which causes errors or are for initilisation
*
*************************************************************************************************************************;

%************************************************************************************************************************;
%**                                                                                                                    **;
%** License: MIT                                                                                                       **;
%**                                                                                                                    **;
%** Copyright (c) 2020 Katja Glass                                                                                     **;
%**                                                                                                                    **;
%** Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated       **;
%** documentation files (the "Software"), to deal in the Software without restriction, including without limitation    **;
%** the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and   **;
%** to permit persons to whom the Software is furnished to do so, subject to the following conditions:                 **;
%**                                                                                                                    **;
%** The above copyright notice and this permission notice shall be included in all copies or substantial portions of   **;
%** the Software.                                                                                                      **;
%**                                                                                                                    **;
%** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO   **;
%** THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE     **;
%** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,**;
%** TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE     **;
%** SOFTWARE.                                                                                                          **;
%************************************************************************************************************************;


%LET drive = /folders/myshortcuts/git/define-xmlmap;
OPTIONS LS=200;

%* Macro to print all datasets from a library to an HTML file;
%MACRO print_all_datasets_in_lib (lib=,outfile=);
	%GLOBAL datasets;
	PROC SQL NOPRINT;
		SELECT memname INTO :datasets SEPARATED BY " " FROM dictionary.tables WHERE libname = "%UPCASE(&lib)";
	RUN;QUIT;
	
	%MACRO print_all_data();
		%DO i = 1 %TO %SYSFUNC(COUNTW(&datasets%STR( )));
			TITLE2 "Dataset: %SCAN(&datasets,&i)";
			PROC PRINT WIDTH=min DATA=&lib..%SCAN(&datasets,&i);
			RUN;
		%END;
	%MEND;
	
	ODS HTML FILE = "&outfile";
	%print_all_data();
	ODS HTML CLOSE;
%MEND print_all_datasets_in_lib;


%***************************************************************;
%* SDTM Define Example (pure mapping);
%***************************************************************;

filename define url "https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data/sdtm/TDF_SDTM_v1.0/define.xml";
filename xmlmap "&drive/map_files/define_2_0_0.map";
libname define xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

TITLE1 "SDTM Example - mapped libname content";
%print_all_datasets_in_lib (lib=DEFINE,outfile=&drive/examples/output_example_sdtm_pure.html);

	
%***************************************************************;
%* ADAM Define Example (pure mapping);
%***************************************************************;

filename define url "https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data/adam/TDF_ADaM_v1.0/define.xml";
filename xmlmap "&drive/map_files/define_2_0_0.map";
libname define xmlv2 xmlmap=xmlmap access=READONLY compat=yes;

TITLE1 "ADAM Example - mapped libname content";
%print_all_datasets_in_lib (lib=DEFINE,outfile=&drive/examples/output_example_adam_pure.html);


%***************************************************************;
%* Download example files;
%***************************************************************;

%* download adam and sdtm define.xml files for tests;
FILENAME out "&drive/examples/out_sdtm/define.xml";
PROC HTTP
 	URL='https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data/sdtm/TDF_SDTM_v1.0/define.xml'
 	METHOD="get" OUT=out;
RUN;
FILENAME out;
FILENAME out "&drive/examples/out_adam/define.xml";
PROC HTTP
 	URL='https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data/adam/TDF_ADaM_v1.0/define.xml'
 	METHOD="get" OUT=out;
RUN;
FILENAME out;


%***************************************************************;
%* SDTM Define Example (mapping & macro processing);
%***************************************************************;

libname metalib "&drive/examples/out_sdtm";
%INCLUDE "&drive/examples/define_2_0_0.sas";
%define_2_0_0(define = &drive/examples/out_sdtm/define.xml,
              xmlmap  = &drive/map_files/define_2_0_0.map);
        

%print_all_datasets_in_lib (lib=metalib,outfile=&drive/examples/output_example_sdtm.html);        
        
             
%***************************************************************;
%* ADAM Define Example (mapping & macro processing);
%***************************************************************;

libname metalib "&drive/examples/out_adam";
%INCLUDE "&drive/examples/define_2_0_0.sas";
%define_2_0_0(define = &drive/examples/out_adam/define.xml,
              xmlmap  = &drive/map_files/define_2_0_0.map);       
             
%print_all_datasets_in_lib (lib=metalib,outfile=&drive/examples/output_example_adam.html);                     
             
