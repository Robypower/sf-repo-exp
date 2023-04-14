/**
 * Main controller for Generic Form Application
 *
 * @author      Onkar Pawar <onkar.doc@gmail.com>
 * @version     1.0
 * @since       1.0
 */
public without sharing class GenericFormController {
    
    static Map<String, Schema.SObjectField> allFields;
    static Map<String,ColumnField> fieldMap = new Map<String,ColumnField>();
    static Map<String,ColumnField> picklisFieldtMap = new Map<String,ColumnField>();
    static Map<String,ColumnField> picklistControllerFieldMap = new Map<String,ColumnField>();
    Map<String,String> flddNameToCtrlFldNameMap = new Map<String,String>();

    private static final String base64Chars = '' +'ABCDEFGHIJKLMNOPQRSTUVWXYZ' + 'abcdefghijklmnopqrstuvwxyz' + '0123456789+/';

    /**
    * Returns generated FormWrapper to UI component.
    *
    * <p>Use {@link #validateWrapper(FormWrapper wrapper)} to validate request wrapper.
    *
    * @param wrapper  Request FormWrapper with basic details for Response FormWrapper generation.
    * @return         generated FormWrapper or with appropriate errorMessage in case of failure.
    * @since          1.0
    */
    @AuraEnabled
    public static FormWrapper get_Form_Wrapper(FormWrapper wrapper) {

        if(validateWrapper(wrapper)){ //
            Boolean processedSuccessfully = generate_Form_Wrapper(wrapper);
            
        }

        return wrapper;
    }

    /**
    * Generates FormWrapper from request.
    *
    * @param wrapper  Request FormWrapper with basic details for request parameter generation.
    * @return         true if FormWrapper generated successfully otherwise false and appropriate errorMessage in wrapper.
    * @since          1.0
    */
    public static Boolean generate_Form_Wrapper(FormWrapper wrapper){
        Boolean processedSuccessfully = true;
        try{
            List<Schema.DescribeSObjectResult> describeSobjectsResult = Schema.describeSObjects(new List<String>{wrapper.objectName});
           allFields = describeSobjectsResult[0].fields.getMap();
             /**
            * Page Layout metadata list.
            */
            List<Metadata.Metadata> layouts = Metadata.Operations.retrieve(Metadata.MetadataType.Layout,new List<String> {wrapper.objectName+'-'+wrapper.layoutName});
            Metadata.Layout layoutMd = (Metadata.Layout) layouts.get(0);
            wrapper.layoutSections = new List<LayoutSection>();

            for (Metadata.LayoutSection section : layoutMd.layoutSections) {  
                LayoutSection layoutSection = populate_LayoutSection(section);
                if(layoutSection != null){
                    wrapper.layoutSections.add(layoutSection);
                }
            }

            for(String picklistFieldName: picklistControllerFieldMap.keySet()){
                ColumnField dependentField = picklisFieldtMap.get(picklistFieldName);
                ColumnField controllerField = picklistControllerFieldMap.get(picklistFieldName);
                if(dependentField != null && controllerField != null && dependentField.isDependent){
                    controllerField.isController = true;
                    controllerField.dependentField = controllerField.APIName;
                }
            }

        }catch(Exception e){
            processedSuccessfully = false;
            wrapper.errorMessage = '{"method":"generate_Form_Wrapper","errorMessage":"'+e.getMessage()+'","lineNumber":"'+e.getLineNumber()+'"}';
        }
        return processedSuccessfully;
    }

    /**
    * Populates LayoutSection from Layout Metadata.
    *
    * @param section  Metadata.LayoutSection object.
    * @return         pupulated LayoutSection object.
    * @since          1.0
    */
    public static LayoutSection populate_LayoutSection(Metadata.LayoutSection section){
        LayoutSection layoutSection = new LayoutSection();
        layoutSection.label = section.label;
        layoutSection.editableFieldFound = false;
        layoutSection.fieldCount = 0;
        Integer columnIndex = 0;
        for (Metadata.LayoutColumn column : section.layoutColumns) {
            LayoutColumn layoutColumn = populate_LayoutColumn(column,++columnIndex);
            if(layoutColumn != null){
                if(layoutColumn.editableFieldFound){
                    layoutSection.editableFieldFound = true;
                }
                layoutSection.fieldCount += layoutColumn.fields.size();
                layoutSection.columns.add(layoutColumn);
            }
        }
        return layoutSection;
    }

    /**
    * Populates LayoutColumn from Metadata.LayoutColumn object.
    *
    * @param column         Metadata.LayoutColumn object.
    * @param columnIndex    Defines column position on UI.
    * @return               pupulated LayoutColumn object.
    * @since                1.0
    */
    public static LayoutColumn populate_LayoutColumn(Metadata.LayoutColumn column,Integer columnIndex){
        LayoutColumn layoutColumn = new LayoutColumn();
        layoutColumn.columnIndex = columnIndex;
        layoutColumn.fieldCount = 0;
        layoutColumn.editableFieldFound = false;

        if (column.layoutItems != null) {
            for (Metadata.LayoutItem layoutItem : column.layoutItems) {
                ColumnField columnField  = populate_ColumnField(layoutColumn,layoutItem);
                if(columnField != null){
                    layoutColumn.fields.add(columnField);
                }
            }
        }
        return layoutColumn;
    }

    /**
    * Populates ColumnField from Metadata.LayoutItem object.
    *
    * @param layoutColumn   LayoutColumn object.
    * @param layoutItem     Metadata.LayoutItem object.
    * @return               pupulated ColumnField object.
    * @since                1.0
    */
    public static ColumnField populate_ColumnField(LayoutColumn layoutColumn,Metadata.LayoutItem layoutItem){
        ColumnField columnField = new ColumnField();
        if(layoutItem != null && String.isNotBlank(layoutItem.field)){
            Schema.DescribeFieldResult fieldData = allFields.get(layoutItem.field).getDescribe();
            columnField.columnIndex=layoutColumn.columnIndex;
            columnField.APIName = layoutItem.field;
            columnField.dataType = String.valueOf(fieldData.getType());
            columnField.fieldType = determineUIFieldType(fieldData.getType());
            columnField.label = fieldData.getLabel();
            
            if('address'.equals(columnField.fieldType) ){
                //return null; // skiping Address data type for now
            }
            if('REFERENCE'.equals(columnField.dataType)){
                if(fieldData.referenceto != null && fieldData.referenceto.size() > 0){
                    columnField.referenceto = String.valueOf( fieldData.referenceto.get(0));
                }
                //return null; // skipping lookup field type for now
            }
            
            if(fieldData.getType() == Schema.DisplayType.TEXTAREA && fieldData.isHtmlFormatted()){
                columnField.fieldType = 'inputRich';
                columnField.formats = new List<String>{'font', 'size', 'bold', 'italic', 'underline', 'strike','list', 'indent', 'align', 'link', 'image', 'clean', 'table','header', 'color', 'background', 'code', 'code-block', 'script','blockquote','direction'};
            }

            if(fieldData.getType() == Schema.DisplayType.CURRENCY){
                columnField.formatter = 'currency';
            }

            switch on layoutItem.behavior{
                when Edit{
                    layoutColumn.editableFieldFound = true;
                    columnField.disabled=false;
                    columnField.required=false;
                }
                when Readonly{
                    columnField.disabled=true;
                    columnField.required=false;
                }
                when Required{
                    layoutColumn.editableFieldFound = true;
                    columnField.disabled=false;
                    columnField.required=true;
                }
            }

            if('PICKLIST' == String.valueOf(fieldData.getType()) || 'MULTIPICKLIST' == String.valueOf(fieldData.getType()) || 'Boolean' == String.valueOf(fieldData.getType()) ){
                picklistControllerFieldMap.put(layoutItem.field,columnField);
                if(fieldData.getController()!=null){
                    columnField.isDependent=true;
                    columnField.masterField = String.valueOf(fieldData.getController());
                    picklisFieldtMap.put(columnField.masterField,columnField);
                    Schema.SObjectField ctrlField = allFields.get(columnField.masterField);
                    List<Schema.PicklistEntry> contrEntries = ctrlField.getDescribe().getPicklistValues();                                    
                    List<PicklistEntryWrapper> depEntries = wrapPicklistEntries(fieldData.getPicklistValues());
                    List<String> controllingValues = new List<String>();
                    Boolean checkboxIsCtrl = false;
                    if('Boolean' == String.valueOf(ctrlField.getDescribe().getType()) ){
                        controllingValues.add('true');
                        controllingValues.add('false');
                        columnField.picklistMap.put('true', new List<PicklistItem>());
                        columnField.picklistMap.put('false', new List<PicklistItem>());
                        checkboxIsCtrl = true;
                    }
                    for(Schema.PicklistEntry ple1 : contrEntries) {
                        String label = ple1.getLabel();
                        columnField.picklistMap.put(label, new List<PicklistItem>());
                        controllingValues.add(label);
                    }
                    for (PicklistEntryWrapper plew : depEntries) {
                        String validForBits = base64ToBits(plew.validFor);
                        for (Integer i = 0; i < validForBits.length(); i++) {
                            String bit = validForBits.mid(i, 1);
                            if (bit == '1') {
                                System.debug('controllingValues->'+controllingValues);
                                columnField.picklistMap.get(controllingValues.get(i)).add(new PicklistItem(plew.label,plew.value));
                            }
                        }
                    }
                    if(checkboxIsCtrl){
                        List<PicklistItem> tmp = columnField.picklistMap.get('true');
                        columnField.picklistMap.put('true',columnField.picklistMap.get('false'));
                        columnField.picklistMap.put('false',tmp);
                    }
                }
                else{                                    
                    List<Schema.PicklistEntry> ple = fieldData.getPicklistValues();
                    for( Schema.PicklistEntry pickOption : ple){
                        columnField.picklistOptions.add(new PicklistItem(pickOption.getLabel(),pickOption.getValue()));
                    }
                } 
            }

            if('location'.equals(columnField.fieldType)){
                String apiN = layoutItem.field.removeEnd('c');
                fieldMap.put(apiN+'Latitude__s',columnField);
                fieldMap.put(apiN+'Longitude__s',columnField);                                
            }
            else{
                fieldMap.put(layoutItem.field,columnField);
            } 


        }
        return columnField;
    }

    /**
    * Determines UI field type from Schema.DisplayType.
    *
    * @param dataType     Schema.DisplayTypeobject.
    * @return            pupulated UI element field type.
    * @since             1.0
    */
    public static String determineUIFieldType(Schema.DisplayType dataType){
        switch on dataType{
            when String,ID{
                return 'text';
            }
            when TextArea,base64{
                return 'textarea';
            }
            when address{
                return 'address';
            }
            when Boolean{
                return 'checkbox';
            }
            when Date{
                return 'date';
            }
            when DateTime{
                return 'datetime';
            }
            when Time{
                return 'time';
            }
            when Phone{
                return 'tel';
            }
            when Double,Integer,Long,Percent,CURRENCY{
                return 'number';
            }
            when Picklist{
                return 'picklist';
            }
            when Reference{
                return 'text';
            }
            when Email{
                return 'email';
            }
            when URL{
                return 'url';
            }
            when MULTIPICKLIST{
                return 'multipicklist';
            }
            when ENCRYPTEDSTRING{
                return 'password';
            }
            when LOCATION{
                return 'location';
            }
        }
        return 'text';
    }

    public static String base64ToBits(String validFor) {
        if (String.isEmpty(validFor)) return '';
        
        String validForBits = '';
        
        for (Integer i = 0; i < validFor.length(); i++) {
            String thisChar = validFor.mid(i, 1);
            Integer val = base64Chars.indexOf(thisChar);
            String bits = decimalToBinary(val).leftPad(6, '0');
            validForBits += bits;
        }
        
        return validForBits;
    }

    public static String decimalToBinary(Integer val) {
        String bits = '';
        while (val > 0) {
            Integer remainder = Math.mod(val, 2);
            val = Integer.valueOf(Math.floor(val / 2));
            bits = String.valueOf(remainder) + bits;
        }
        return bits;
    }
    
    
    
    
    private static List<PicklistEntryWrapper> wrapPicklistEntries(List<Schema.PicklistEntry> PLEs) {
        return (List<PicklistEntryWrapper>)
            JSON.deserialize(JSON.serialize(PLEs), List<PicklistEntryWrapper>.class);
    }
    

    /**
    * Validates FormWrapper request parametewrs.
    *
    * @param wrapper  Request FormWrapper with basic details for request parameter validation.
    * @return         true if required parameters are valid otherwise false and appropriate errorMessage in wrapper.
    * @since          1.0
    */
    static Boolean validateWrapper(FormWrapper wrapper){
        Boolean valid = true;
        if(wrapper != null){
            wrapper.errorMessage = '';
            if(String.isBlank(wrapper.objectName) || String.isBlank(wrapper.layoutName)){
                wrapper.errorMessage = '{"method":"validateWrapper","errorMessage":"Required information missing objectName/layoutName.","lineNumber":""}';
                valid = false;
            }
        }

        if(wrapper == null){
            wrapper = new FormWrapper();
            wrapper.errorMessage = '{"method":"validateWrapper","errorMessage":"Empty request received.","lineNumber":""}';
            valid = false;
        }
        return valid;
    }

  
/**
 * Data Wrapper for Generic Form Application
 *
 * @author      Onkar Pawar <onkar.doc@gmail.com>
 * @version     1.0
 * @since       1.0
 */
    public class FormWrapper{
        /**
        * Request parameter.
        * Salesforce Record Id for Record Edit operation.
        */
        @AuraEnabled
        public String recordId {get;set;}

        /**
        * Required Request parameter.
        * Salesforce sObject Name for New Record/Record Edit operation.
        */
        @AuraEnabled
        public String objectName {get;set;}

        /**
        * Required Request parameter.
        * Salesforce sObject Page Layout Name for New Record/Record Edit operation.
        */
        @AuraEnabled
        public String layoutName {get;set;}

        /**
        * Response parameter.
        * Error message in case of failed operation.
        */
        @AuraEnabled
        public String errorMessage {get;set;}

        /**
        * Response parameter.
        * List of LayoutSection in Page Layout.
        */
        @AuraEnabled
        public List<LayoutSection> layoutSections {get;set;}
    }

    /**
    * LayoutSection Data for FormWrapper
    *
    * @author      Onkar Pawar <onkar.doc@gmail.com>
    * @version     1.0
    * @since       1.0
    */
    public class LayoutSection{
        @AuraEnabled
        public String label {get;set;}
        @AuraEnabled
        public Integer fieldCount {get;set;}
        @AuraEnabled
        public Boolean editableFieldFound {get;set;}
        @AuraEnabled
        public List<LayoutColumn> columns {get;set;}
        public LayoutSection(){
            this.columns = new List<LayoutColumn>();
        }
        // public LayoutSection(List<LayoutColumn> columns,String label,Integer fieldCount,Boolean editableFieldFound){
        //     this.columns = columns;
        //     this.label = label;
        //     this.editableFieldFound = editableFieldFound;
        //     this.fieldCount = fieldCount;
        // }
    }

    /**
    * LayoutColumn data for LayoutSection
    *
    * @author      Onkar Pawar <onkar.doc@gmail.com>
    * @version     1.0
    * @since       1.0
    */
    public class LayoutColumn{
        @AuraEnabled
        public Integer columnIndex {get;set;}
        @AuraEnabled
        public Integer fieldCount {get;set;}
        @AuraEnabled
        public Boolean editableFieldFound {get;set;}
        @AuraEnabled
        public List<ColumnField> fields {get;set;}
        public LayoutColumn(){
            this.fields = new List<ColumnField>();
        }
        public LayoutColumn(List<ColumnField> fields){
            this.fields = fields;
        }
    }

    /**
    * ColumnField data for LayoutColumn
    *
    * @author      Onkar Pawar <onkar.doc@gmail.com>
    * @version     1.0
    * @since       1.0
    */
    public class ColumnField{
        @AuraEnabled
        public Integer columnIndex {get;set;}
        @AuraEnabled
        public String label {get;set;}
        @AuraEnabled
        public String APIName {get;set;}
        @AuraEnabled
        public String fieldType {get;set;}
        @AuraEnabled
        public Boolean disabled {get;set;}
        @AuraEnabled
        public Boolean required {get;set;}
        @AuraEnabled
        public Boolean visible {get;set;}
        @AuraEnabled
        public List<PicklistItem> picklistOptions {get;set;}
        @AuraEnabled
        public Object value {get;set;}
        @AuraEnabled
        public String masterField {get;set;}
        @AuraEnabled
        public Map<String,List<PicklistItem>> picklistMap {get;set;}
        @AuraEnabled
        public Boolean isDependent {get;set;}
        @AuraEnabled
        public Boolean isController {get;set;}
        @AuraEnabled
        public String dependentField {get;set;}
        @AuraEnabled
        public String dataType {get;set;}
        @AuraEnabled
        public String referenceto {get;set;}
        @AuraEnabled
        public AddressFormat address {get;set;}
        @AuraEnabled
        public String formatter {get;set;}
        @AuraEnabled
        public List<String> values {get;set;}
        @AuraEnabled
        public List<String> formats {get;set;}    
        @AuraEnabled
        public String latitude {get;set;}
        @AuraEnabled
        public String longitude {get;set;}
        @AuraEnabled
        public String lookupRecordName {get;set;}
        @AuraEnabled
        public String lookupObjStr {get;set;}           
        public ColumnField(){
            label='';
            APIName='';
            formatter='';
            fieldType='';
            disabled=true;
            visible=true;
            required=true;
            picklistOptions=new List<PicklistItem>();
            value ='';
            masterField ='';
            picklistMap=new Map<String,List<PicklistItem>>();
            isDependent=false;
            isController=false;
            dataType='';
            referenceto = '';
            address = new AddressFormat();
            values = new List<String>();
            formats = new List<String>();
            longitude = '';
            latitude = '';
            lookupRecordName = '';
            lookupObjStr = '';
        }   
    }

    /**
    * AddressFormat data for Field
    *
    * @author      Onkar Pawar <onkar.doc@gmail.com>
    * @version     1.0
    * @since       1.0
    */
    public class AddressFormat{
        @AuraEnabled
        public String street {get;set;}
        @AuraEnabled
        public String city {get;set;}
        @AuraEnabled
        public String country {get;set;}
        @AuraEnabled
        public String postalCode {get;set;}
        @AuraEnabled
        public String province {get;set;}
        public AddressFormat(){}
        public AddressFormat(String street,String city,String country,String postalCode,String province){
            this.street=street;
            this.city=city;
            this.country=country;
            this.postalCode=postalCode;
            this.province=province;
        }        
    }

    /**
    * PicklistItem data for Field
    *
    * @author      Onkar Pawar <onkar.doc@gmail.com>
    * @version     1.0
    * @since       1.0
    */
    public class PicklistItem{
        @AuraEnabled
        public String label {get;set;}
        @AuraEnabled
        public String value {get;set;}
        public PicklistItem(){}
        public PicklistItem(String label,String value){
            this.label=label;
            this.value=value;
        }
    }

    public class PicklistEntryWrapper{
        public String active {get;set;}
        public String defaultValue {get;set;}
        public String label {get;set;}
        public String value {get;set;}
        public String validFor {get;set;}
        public PicklistEntryWrapper(){            
        }        
    }

}