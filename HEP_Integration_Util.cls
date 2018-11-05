/**
* HEP_Integration_Util --- Class contains all the generic code required for integrations 
* @author    Tejaswini Veliventi
*/
public without sharing class HEP_Integration_Util {

    private static HEP_Services__c objAuthService {get;set;}

    /**
    * Retrieves the OAuth Token for the HTTP callouts 
    * @param    sServiceName- Name of custome Setting record which stores the Details of OAuth end point.
    * @return   Token type and Access token
    */
    public static String getAuthenticationToken(String sServiceName){
        String sStatus;
        objAuthService = HEP_Services__c.getInstance(sServiceName);
        AccessTokenWrapper objWrapper = new AccessTokenWrapper();
        if(objAuthService != null){
            HttpRequest objReq = new HttpRequest();
            String sEndPoint = objAuthService.Endpoint_URL__c + objAuthService.Service_URL__c;
            //Building the http request with detials from custom settng
            objReq.setEndpoint(sEndPoint);
            objReq.setMethod(getConstantValue('HEP_METHOD_POST'));
            objReq.setTimeout(Integer.valueOf(getConstantValue('HEP_SET_TIMEOUT')));
            objReq.setBody(getConstantValue('HEP_GRANT_TYPE') + objAuthService.Service_Account_ID__c + 
                        getConstantValue('HEP_CLIENT_ID') + objAuthService.Client_Id__c +
                        getConstantValue('HEP_CLIENT_SECRET') + objAuthService.Client_Secret__c);
            objReq.setHeader(getConstantValue('HEP_CONTENT_TYPE') , getConstantValue('HEP_URL_ENCODED'));
            Http objHttp = new HTTP();
            try{
                HttpResponse objRes = objHttp.send(objReq);
                String sResponseBody = objRes.getBody(); 
                System.debug('response..' + sResponseBody);
                sStatus = objRes.getStatus();
                //Assign HTTP status to global constants so that in respective class this status can be checked for success
                if (sStatus.equals(getConstantValue('HEP_STATUS_OK'))) {
                    objWrapper = (AccessTokenWrapper)Json.deserialize( sResponseBody , AccessTokenWrapper.class );
                } 
                else {
                  HEP_Error_Log.BusinessException(getConstantValue('HEP_OAUTH_SERVICE_ERROR'), getConstantValue('HEP_INTEGRATION_OUTBOUND') ,
                                                   sStatus, '', getConstantValue('HEP_INTEGRATION_UTIL'), getConstantValue('HEP_RETRIEVE_OAUTH'), '', '');
                  return sStatus;
                }
            }
            //create error log record on exception
            catch(Exception excep){
                System.debug('Exception at line : ' + excep.getLineNumber() + ' ' + excep.getMessage() );
                HEP_Error_Log.genericException(getConstantValue('HEP_OAUTH_OUTBOUND_EXCEPTION'), getConstantValue('HEP_INTEGRATION_OUTBOUND'), excep,
                                               getConstantValue('HEP_INTEGRATION_UTIL') , getConstantValue('HEP_RETRIEVE_OAUTH'), '', '');
                return 'Exception';
            }
        }
        //custom setting data not found, then return null
        else{
            System.debug('Error - Can not find custom Setting Entry for Authentication');
            return null;
        }
        //return the tokentype+ token 
        String sFinalReturnValue;
        if(objWrapper.token_type != null && objWrapper.access_token != null){
          sFinalReturnValue = objWrapper.token_type + ' ' + objWrapper.access_token;
        }
        return sFinalReturnValue;
    }
    
    
    /**
    * updateInterfaceTransactionError --- Creates interface txn error record
    * @param    objIntTxnResponse an instance of interface txn response class
    * @return   nothing
    */
    public static void updateInterfaceTransactionError(HEP_InterfaceTxnResponse objIntTxnResponse){
        if(objIntTxnResponse != null){
            // Create an instance of HEP_Interface_Transaction_Error__c
            HEP_Interface_Transaction_Error__c objIntTxnError = new  HEP_Interface_Transaction_Error__c();
            objIntTxnError.Status__c = objIntTxnResponse.sStatus;
            objIntTxnError.Error_Datetime__c = System.now();
            if(objIntTxnResponse.sErrorMsg != null){
                objIntTxnError.Error_Description__c = String.valueof(objIntTxnResponse.sErrorMsg).left(32765);      
            }     
            objIntTxnError.HEP_Interface_Transaction__c = objIntTxnResponse.sInterfaceTxnId;
            // Inserting the record
            insert objIntTxnError;
            //For content Version        
            map<String, blob> mapContentBodies = new map<String, blob>();
            if(objIntTxnResponse.sResponse != null)
                mapContentBodies.put(getConstantValue('HEP_INTEGRATION_RESPONSE'), blob.valueof(String.valueof(objIntTxnResponse.sResponse)));
            if(objIntTxnResponse.sRequest != null)    
                mapContentBodies.put(getConstantValue('HEP_INTEGRATION_REQUEST'), blob.valueof(String.valueof(objIntTxnResponse.sRequest)));
            String sContentType = getConstantValue('HEP_CONTENT_TYPE_PDF');
            createFile(objIntTxnError.id, mapContentBodies, sContentType);
        }        
    }
 
 
    /**
    * Creates a SingleEmailMessage for every interface transaction error record
    * @param    Takes HTTPRequest , HTTPResponse as parameter
    * @return   Messaging.SingleEmailMessage Object instance
    */
    public static Messaging.SingleEmailMessage createSingleEmailMessage(List<string> lstToAddresses, Id TargetObjectId, Id WhatId, Id TemplateId, List<Messaging.Emailfileattachment> lstFileAttachments){
        Messaging.SingleEmailMessage objMessage = new Messaging.SingleEmailMessage();
        objMessage.setToAddresses(lstToAddresses);  
        objMessage.setTargetObjectId(TargetObjectId); //The first Team Member ID found, this email address will not be in the emailList
        objMessage.setWhatId(WhatId);
        objMessage.setTemplateId(TemplateId);
        objMessage.SaveAsActivity = false;
        objMessage.setFileAttachments(lstFileAttachments);
        return objMessage;
    }
    
    
    /**
    * createInterfaceTxn --- Creates a new interface transaction record
    * @param    objIntTxnResponse 
    * @return   the interface txn record id
    */
    public static void createInterfaceTxn(HEP_InterfaceTxnResponse objIntTxnResponse){
        try{
            HEP_Interface_Transaction__c objIntTxn;
            // If the transaction id is not there, then we need to insert it, otherwise we need to update it
            if(String.isNotBlank(objIntTxnResponse.sInterfaceTxnId)){
                objIntTxn = new  HEP_Interface_Transaction__c(id = objIntTxnResponse.sInterfaceTxnId);
                if(objIntTxnResponse.iMaxRetriesAllowed > 0){
                    objIntTxn.Retry_Count__c = objIntTxnResponse.iCurrentNoOfRetries + 1;
                }
            }
            else{
                objIntTxn = new  HEP_Interface_Transaction__c();
                objIntTxn.Retry_Count__c = 1;   
                objIntTxn.Transaction_Datetime__c = System.now(); 
            }   
            objIntTxn.HEP_Interface__c = objIntTxnResponse.sInterfaceId;
            if(objIntTxnResponse.bIsSourceAsAttachment != true){
                if(String.isNotEmpty(objIntTxnResponse.sSourceId) && objIntTxnResponse.sSourceId.length() > 254){
                    objIntTxn.Object_Id__c = objIntTxnResponse.sSourceId.substring(0, 254);
                }
                else{
                    objIntTxn.Object_Id__c = objIntTxnResponse.sSourceId;
                }
            }             
            objIntTxn.Status__c = objIntTxnResponse.sStatus;            
            if(objIntTxnResponse.sStatus == getConstantValue('HEP_FAILURE') && objIntTxnResponse.iMaxRetriesAllowed > objIntTxn.Retry_Count__c){
                objIntTxn.Next_Retry_Time__c = System.now().addMinutes(objIntTxnResponse.iRetryInterval);
            }
            // Upsert the interface txn record
            upsert objIntTxn;
            if(objIntTxnResponse.bIsSourceAsAttachment == true){
                if(String.isEmpty(objIntTxn.Object_Id__c)){
                    map<String, list<string>> mapParentIdsFileNames = new map<String, list<string>>();
                    list<String> lstFileName = new list<String>();
                    lstFileName.add(HEP_Integration_Util.getConstantValue('HEP_INTEGRATION_SOURCE')); 
                    mapParentIdsFileNames.put(objIntTxn.Id,lstFileName);
                    map<String, map<string, string>> mapContentDocumentOutput = HEP_Integration_Util.retriveDatafromContentBulkified(mapParentIdsFileNames);
                    if((mapContentDocumentOutput.keyset()).isEmpty()){
                        map<String, blob> mapContentBodies = new map<String, blob>();
                        mapContentBodies.put(getConstantValue('HEP_INTEGRATION_SOURCE'), blob.valueof(objIntTxnResponse.sSourceId)); 
                        String sContentType = getConstantValue('HEP_CONTENT_TYPE_PDF');
                        //to check if content file needs to be created --Roshi
                        if(objIntTxnResponse.bIsCreateContentFile)
                        createFile(String.valueOf(objIntTxn.id), mapContentBodies, sContentType); 
                    }
                }
            }    
            // If the transaction has failed, create error record
            if(objIntTxnResponse.sStatus == getConstantValue('HEP_FAILURE')){
                objIntTxnResponse.sInterfaceTxnId = objIntTxn.id;
                updateInterfaceTransactionError(objIntTxnResponse);
                // If its an inbound txn and the txn is failure, even then add the content records for request and response ----Roshi
                if(objIntTxnResponse.bInboundTxn && objIntTxnResponse.bIsCreateContentFile){
                    createContentRecords(objIntTxnResponse.sRequest, objIntTxnResponse.sResponse, String.valueOf(objIntTxn.id) , objIntTxnResponse.sSourceId,objIntTxnResponse.bIsSourceAsAttachment ,objIntTxnResponse.bInboundTxn);
                }
            } 
            else if(objIntTxnResponse.bIsCreateContentFile){
                // If the txn is successful and create content file is true then add the content records for request and response ----Roshi
                createContentRecords(objIntTxnResponse.sRequest, objIntTxnResponse.sResponse, String.valueOf(objIntTxn.id) , objIntTxnResponse.sSourceId, objIntTxnResponse.bIsSourceAsAttachment ,objIntTxnResponse.bInboundTxn);                
            }
            System.debug('objIntTxn.id'+objIntTxn.id);      
        }catch(exception ex){
            System.debug('Exception at line ' + ex.getLinenumber() + 'Exception message ' + ex.getMessage());
            HEP_Error_Log.genericException('Error in creating interface txn','DML errors', ex, 'HEP_Integration_Util', 'createInterfaceTxn','','');
        }        
    }
     

    /**
    * createContentRecords --- Creates content object records for request and response
    * @param    sRequest - request body
    * @param    sResponse - response body
    * @param    sParentId - id of the parent record to which content object is to be associated
    * @return   nothing
    */
    public static void createContentRecords(String sRequest, String sResponse, String sParentId,String sSourceId, Boolean bIsSourceAsAttachment,Boolean bInboundTxn){
        // Add request and response to the transaction record if its successful        
        map<String, blob> mapContentBodies = new map<String, blob>(); 
        if(sResponse != null)
            mapContentBodies.put(getConstantValue('HEP_INTEGRATION_RESPONSE'), blob.valueof(sResponse));
        if(sRequest != null)    
            mapContentBodies.put(getConstantValue('HEP_INTEGRATION_REQUEST'), blob.valueof(sRequest));
        String sContentType = getConstantValue('HEP_CONTENT_TYPE_PDF');
        
        createFile(sParentId, mapContentBodies, sContentType);
    }
    

    /**
    * create File to store request-response of interface transaction in salesforce 
    * @param    objIntTxnResponse - parentId-id of transaction Error, map --> fileName- name of the file, body - request or response value, contentType - Content type
    * @return   Void
    */
    public static void createFile(Id parentId, map<String, Blob> mapBodies, String sContentType) {
        Savepoint objSavePoint = Database.setSavepoint();
        try{
            if(parentId != null && mapBodies != null){
                // insert a version of the file - if no ContentDocumentId, then it creates a new ContentDocument
                list<ContentVersion> lstContentVersions = new list<ContentVersion>();
                
                for(String sFileName : mapBodies.keyset()){
                    
                    ContentVersion objContentVersion = new ContentVersion();
                    objContentVersion.ContentLocation = getConstantValue('HEP_CURRENT_LOCATION_S'); // S = within Salesforce, E = External
                    objContentVersion.VersionData = mapBodies.get(sFileName);
                    objContentVersion.Title = sFileName;
                    //cv1.ContentType = contentType;
                    objContentVersion.PathOnClient = sFileName;
                    if(mapBodies.get(sFileName) != null && !String.isEmpty(mapBodies.get(sFileName).toString()))
                        lstContentVersions.add(objContentVersion);
                }
                if(lstContentVersions != null && !lstContentVersions.isEmpty()){
                    insert lstContentVersions;   
                    // insert a ContentDocumentLink with the fiel version
                    list<ContentVersion> lstContentVersion = [SELECT Id, ContentDocumentId 
                                                              FROM ContentVersion 
                                                              WHERE Id IN :lstContentVersions];                                              
                    list<ContentDocumentLink> lstContentDocList = new list<ContentDocumentLink>();
                    for(ContentVersion objContentVersion : lstContentVersion){
                        ContentDocumentLink objContentDocLink = new ContentDocumentLink();
                        objContentDocLink.ContentDocumentId = objContentVersion.ContentDocumentId;
                        objContentDocLink.LinkedEntityId = parentId;
                        objContentDocLink.ShareType = getConstantValue('HEP_SHARE_TYPE_V');
                        lstContentDocList.add(objContentDocLink);
                    }
                    System.debug('lstContentDocList+++++'+lstContentDocList);
                    if(lstContentDocList != null && !lstContentDocList.isEmpty()){
                        insert lstContentDocList;
                    }        
                }
            }
        }  
        catch(Exception ex){
            System.debug('Exception'+ex);
            Database.rollback(objSavePoint);
            throw ex;
        }                  
    }

    /**
    * saveFileDatainContent --- Create content Version Record and link it to the ParentId
    * @param   Id : Paernt Object Id, map<string, string> (string : FileName, string : Data in string Format), String : FileType
    * @return   set<Id> ContentLink object Ids that links the data in content Version with parent Ids
    */
    public static set<Id>  saveFileDatainContent(Id ParentId, map<string, string> mapFileNameDatas, string sFileType){
        Savepoint objSavePoint = Database.setSavepoint();
        try{
            //All ContentLink Ids to be returns if created 
            set<id> setContentDocumentLinkIds = new set<id>();
            //Checking the Mandatory values to create the Content Varsion Record
            if(ParentId != null && mapFileNameDatas != null){
                //Content Versions to be inserted
                list<ContentVersion> lstContentVersions = new list<ContentVersion>();

                //Loop through all the Datas
                for(string sFileName : mapFileNameDatas.keyset()){
                    //Check if FileName Contains a data against it
                    if(mapFileNameDatas.containskey(sFileName)){
                        //Create the ContentVersion Record
                        ContentVersion objContentVersion = new ContentVersion();
                        objContentVersion.ContentLocation = getConstantValue('HEP_CURRENT_LOCATION_S'); // S = within Salesforce, E = External
                        //objContentVersion.Title = sFileName + '.' + sFileType;
                        objContentVersion.Title = sFileName;
                        //objContentVersion.ContentType = sFileType;
                        objContentVersion.VersionData = blob.valueOf(mapFileNameDatas.get(sFileName));
                        objContentVersion.PathOnClient = sFileName;
                        lstContentVersions.add(objContentVersion);
                    }    
                }    

                if(lstContentVersions != null && !lstContentVersions.isEmpty()){
                    insert lstContentVersions; 

                    // get the content Document Ids to link the document with Content Link
                    list<ContentVersion> lstRetrivedContentVersions = [SELECT Id, ContentDocumentId 
                                                               FROM ContentVersion 
                                                               WHERE Id IN :lstContentVersions];            
                    //Create Document Link records to link the documents with Parent Records
                    list<ContentDocumentLink> lstContentDocLinks = new list<ContentDocumentLink>();
                    for(ContentVersion objContentVersion : lstRetrivedContentVersions){
                        ContentDocumentLink objContentDocLink = new ContentDocumentLink();
                        objContentDocLink.ContentDocumentId = objContentVersion.ContentDocumentId;
                        objContentDocLink.LinkedEntityId = parentId;
                        objContentDocLink.ShareType = getConstantValue('HEP_SHARE_TYPE_V');
                        lstContentDocLinks.add(objContentDocLink);
                    }
                    if(lstContentDocLinks != null && !lstContentDocLinks.isEmpty()){
                        insert lstContentDocLinks;
                        for(ContentDocumentLink objContentDocLink : lstContentDocLinks){
                            setContentDocumentLinkIds.add(objContentDocLink.id);
                        }
                    }
                } 
            }       
            if(setContentDocumentLinkIds != null)
                return setContentDocumentLinkIds;
            else
                return null;
        }catch(exception Ex){
            Database.rollback(objSavePoint);
            throw ex;
            return null;
        }        
    }        

   /**
    * retriveDatafromContent --- Retrive Content version data in string format by ParentId and Name
    * @param   map<id, string> (Id : Paernt Object Id, string : FileName)
    * @return  map<Id, string>(string : Retrived data in string format)
    */
   public static map<String, map<string, string>> retriveDatafromContentBulkified(map<String, list<string>> mapParentIdsFileNames){
        try{
            //All Content version names vs values in string 
            map<string, string> mapContentVersionTitleVsData = new map<string, string>();
            //All Parents Ids to be put in Set - Salesforce restriction
            set<String> setParentIds = mapParentIdsFileNames.keySet();
            //All ParentID related Content Versions
            List<ContentVersion> lstContentVersions = new List<ContentVersion>();
            //Map ContentDocumentID vs ParentIDs
            map<string, string> mapParentIdVsContentDocumentIds = new map<string, string>();
            //MapContentDocumetID vs filename and Datas
            map<String, map<string, string>> mapContentDocIdVsDocDataFileName = new map<String, map<string, string>>();
            //Return values parent Ids against content version data 
            map<String, map<string, string>> mapParentIdvsAllData = new map<String, map<string, string>>();
            //Fetch all file names 
            set<string> setFileNames = new set<string>();

            //Checking the Mandatory values to retrive the Content Datas
            if(mapParentIdsFileNames != null){
                System.debug('I am here 1');
                System.debug('mapParentIdsFileNames : ' + mapParentIdsFileNames);
                if(mapParentIdsFileNames.keySet() != null){
                    system.debug('I am here 2');
                    System.debug('mapParentIdsFileNames.keyset() : ' + mapParentIdsFileNames.keySet());
                    List<ContentDocumentLink> listContentDocumentLinks = [select id, LinkedEntityId, ContentDocumentId from ContentDocumentLink where LinkedEntityId in :setParentIds];
                    system.debug('listContentDocumentLinks : ' + listContentDocumentLinks);
                    system.debug('listContentDocumentLinks.size() : ' + listContentDocumentLinks.size());
                    if(listContentDocumentLinks != null && !listContentDocumentLinks.isEmpty()){
                        system.debug('I am here 3');
                        for(ContentDocumentLink objContentDocLink : listContentDocumentLinks){
                            mapParentIdVsContentDocumentIds.put(objContentDocLink.ContentDocumentId, objContentDocLink.LinkedEntityId);
                        }
                        system.debug('mapParentIdVsContentDocumentIds : ' + mapParentIdVsContentDocumentIds);
                        if(!(mapParentIdVsContentDocumentIds.keyset()).isEmpty()){
                            system.debug('I am here 4');
                            //Get all File Names
                            for(List<string> lstFileNames : mapParentIdsFileNames.values()){
                                for(string fileName : lstFileNames){
                                    setFileNames.add(fileName);
                                }
                            }
                            //Fetching Content version based on ContentDocumentId
                            lstContentVersions = [select id, VersionData,Title,ContentDocumentId from contentVersion where ContentDocumentId in :mapParentIdVsContentDocumentIds.keySet() and Title in :setFileNames];
                        }
                        system.debug('lstContentVersions : ' + lstContentVersions);
                        system.debug('lstContentVersions.size() : ' + lstContentVersions.size());
                        if(lstContentVersions != null && !lstContentVersions.isEmpty()){
                            system.debug('I am here 5');
                            for(ContentVersion objContentVersion : lstContentVersions){
                                if(objContentVersion.VersionData != null){
                                    system.debug('I am here 6');
                                    mapContentVersionTitleVsData = new map<string, string>();
                                    System.debug('objContentVersion.VersionData -----> ' + objContentVersion.VersionData);
                                    mapContentVersionTitleVsData.put(objContentVersion.Title, (objContentVersion.VersionData).toString());
                                    mapContentDocIdVsDocDataFileName.put(objContentVersion.ContentDocumentId, mapContentVersionTitleVsData);
                                }    
                            }
                            system.debug('mapContentDocIdVsDocDataFileName : ' + mapContentDocIdVsDocDataFileName);
                        }
                        if(!(mapParentIdVsContentDocumentIds.Keyset()).isEmpty()){
                            system.debug('I am here 7');
                            for(id ContentDocumentId : mapContentDocIdVsDocDataFileName.Keyset()){
                                if(mapParentIdvsAllData.containsKey(mapParentIdVsContentDocumentIds.get(ContentDocumentId))){
                                    system.debug('I am here 8');
                                    system.debug(' 8 ContentDocumentId : ' + ContentDocumentId);
                                    system.debug('mapParentIdVsContentDocumentIds.get(ContentDocumentId) in IF : ' + mapParentIdVsContentDocumentIds.get(ContentDocumentId));
                                    system.debug('mapContentDocIdVsDocDataFileName : ' + mapContentDocIdVsDocDataFileName.get(ContentDocumentId));
                                    mapParentIdvsAllData.get(mapParentIdVsContentDocumentIds.get(ContentDocumentId)).putAll(mapContentDocIdVsDocDataFileName.get(ContentDocumentId));
                                    system.debug('mapParentIdvsAllData : ' + mapParentIdvsAllData);
                                }
                                else{
                                    system.debug('I am here 9');
                                    system.debug(' 9 ContentDocumentId : ' + ContentDocumentId);
                                    system.debug('mapParentIdVsContentDocumentIds.get(ContentDocumentId) in Else : ' + mapParentIdVsContentDocumentIds.get(ContentDocumentId));
                                    mapParentIdvsAllData.put(mapParentIdVsContentDocumentIds.get(ContentDocumentId),mapContentDocIdVsDocDataFileName.get(ContentDocumentId));
                                    system.debug('mapParentIdvsAllData : ' + mapParentIdvsAllData);
                                }
                                  
                            }
                            system.debug('mapParentIdvsAllData : ' + mapParentIdvsAllData);
                        }
                    }                        
                } 
            } 
            system.debug('Final mapParentIdvsAllData : ' + mapParentIdvsAllData);      
            return mapParentIdvsAllData;
        }catch(exception ex){
            throw ex;
            return null;
        }
    } 
    /**
    * retriveDatafromContent --- Retrive Content version data in string format by ParentId and Name
    * @param   Id : Paernt Object Id, string : FileName
    * @return  string : Retrived data in string format
    */
    public static string retriveDatafromContent(string ParentRecordId, string FileName){
        try{
            set<id> setContentDocumentIds = new set<id>();
            if(ParentRecordId != null && FileName != null && string.isNotEmpty(ParentRecordId) && string.isNotEmpty(FileName)){
                system.debug('I am hetre ');
                List<ContentDocumentLink> listContentDocumentLinks = [select id, LinkedEntityId, ContentDocumentId from ContentDocumentLink where LinkedEntityId = :ParentRecordId];
                for(ContentDocumentLink objContentDocumentLink : listContentDocumentLinks){
                    setContentDocumentIds.add(objContentDocumentLink.ContentDocumentId);
                }
                system.debug('I am here 2');
                //system.debug('listContentDocumentLinks : ' + listContentDocumentLinks);
                if(listContentDocumentLinks != null && !listContentDocumentLinks.isEmpty()){
                    List<contentVersion> lstContentVersions = [select id, VersionData,Title,ContentDocumentId from contentVersion where ContentDocumentId = :setContentDocumentIds and title= :FileName  Order By CreatedDate DESC];
                    system.debug('I am here 3');
                    //system.debug('lstContentVersions : ' + lstContentVersions);
                    if(lstContentVersions != null && !lstContentVersions.isEmpty()){
                        //system.debug('lstContentVersions[0].VersionData.toString() : ' + lstContentVersions[0].VersionData.toString());
                        system.debug('I am here 4');
                        if(lstContentVersions[0].VersionData != null)
                            return lstContentVersions[0].VersionData.toString();
                    }        
                }
            }
            return null;
        }catch(exception ex){
            throw ex;
            return null;
        }
    }
    
    /**
    * updateExistingContent --- update Content version data in string format by ParentId and Name
    * @param   Id : Paernt Object Id, string Filedata(File Content), string : FileName
    * @return  string : Retrived data in string format
    */
    public static string updateExistingContent(string ParentRecordId, string Filedata, string FileName){
        try{
            set<id> setContentDocumentIds = new set<id>();
            if(ParentRecordId != null && FileName != null && string.isNotEmpty(ParentRecordId) && string.isNotEmpty(FileName)){
                system.debug('I am hetre ');
                List<ContentDocumentLink> listContentDocumentLinks = [select id, LinkedEntityId, ContentDocumentId from ContentDocumentLink where LinkedEntityId = :ParentRecordId];
                for(ContentDocumentLink objContentDocumentLink : listContentDocumentLinks){
                    setContentDocumentIds.add(objContentDocumentLink.ContentDocumentId);
                }
                system.debug('listContentDocumentLinks : ' + listContentDocumentLinks);
                if(listContentDocumentLinks != null && !listContentDocumentLinks.isEmpty()){
                    contentVersion objContentVersion = [select id, VersionData,Title,ContentDocumentId from contentVersion where ContentDocumentId = :setContentDocumentIds and title= :FileName limit 1];
                    system.debug('objContentVersion : ' + objContentVersion);
                    if(objContentVersion != null){
                        system.debug('objContentVersion.VersionData.toString() : ' + objContentVersion.VersionData.toString());
                        if(Filedata != null && string.isBlank(Filedata)){
                            objContentVersion.VersionData = blob.valueOf(Filedata);
                            update objContentVersion;
                        }        
                    }        
                }
            }
            return null;
        }catch(exception ex){
            throw ex;
            return null;
        }
    }
    

   /**
    * Helps undating the existing file or create new file if not present agaist the Parent object
    * @param ParentRecordId -- Id against which the documents will be saved or updated
    * @param Filedata -- File content in string format
    * @param FileName -- Name of the file to be saved
    * @return void - No return Value
    * @authod Abhishek Mishra
    */
    public static string upDateExistingorAddNew(string ParentRecordId, string Filedata, string FileName){
        try{
            set<id> setContentDocumentIds = new set<id>();
            if(ParentRecordId != null && Filedata != null && FileName != null && string.isNotEmpty(ParentRecordId) && string.isNotEmpty(FileName) && string.isNotEmpty(Filedata)){
                List<ContentDocumentLink> listContentDocumentLinks = [select id, LinkedEntityId, ContentDocumentId from ContentDocumentLink where LinkedEntityId = :ParentRecordId];                          
                if(listContentDocumentLinks != null && !listContentDocumentLinks.isEmpty()){
                    for(ContentDocumentLink objContentDocumentLink : listContentDocumentLinks){
                        setContentDocumentIds.add(objContentDocumentLink.ContentDocumentId);
                    }
                    List<contentVersion> lstContentVersion = [select id, VersionData,Title,ContentDocumentId 
                                                              from contentVersion 
                                                              where ContentDocumentId = :setContentDocumentIds and title= :FileName and isMajorVersion = false 
                                                              Order By CreatedDate DESC limit 1];
                    if(lstContentVersion != null && !lstContentVersion.isEmpty()){
                        if(Filedata != null && !string.isBlank(Filedata)){
                            lstContentVersion[0].VersionData = blob.valueOf(Filedata);
                            update lstContentVersion[0];
                        }        
                    }else{
                        createNewFile(ParentRecordId, Filedata, FileName);
                    }        
                }else{
                    createNewFile(ParentRecordId, Filedata, FileName);
                }
            }
            return null;
        }catch(exception ex){
           throw ex;
           return null;
        }
    }
    
    /**
    * Helps creating content file againt the parent object
    * @param ParentRecordId -- Id against which the documents will be saved
    * @param Filedata -- File content in string format
    * @param FileName -- Name of the file to be saved
    * @return void - No return Value
    * @authod Abhishek Mishra
    */
    public static void createNewFile(string ParentRecordId, string Filedata, string FileName){
        //Create ContentVersion Record
        ContentVersion objContentVersionRecord = new ContentVersion();
        objContentVersionRecord.ContentLocation = getConstantValue('HEP_CURRENT_LOCATION_S'); // S = within Salesforce, E = External
        objContentVersionRecord.VersionData = blob.valueOf(Filedata);
        objContentVersionRecord.Title = FileName;
        objContentVersionRecord.isMajorVersion = false;
        //cv1.ContentType = contentType;
        objContentVersionRecord.PathOnClient = FileName;
        insert objContentVersionRecord;

        list<ContentVersion> lstContentVersions = [SELECT Id, ContentDocumentId 
                                              FROM ContentVersion 
                                              WHERE Id = :objContentVersionRecord.id];                                              
    
        ContentDocumentLink objContentDocLink = new ContentDocumentLink();
        objContentDocLink.ContentDocumentId = lstContentVersions[0].ContentDocumentId;
        objContentDocLink.LinkedEntityId = ParentRecordId;
        objContentDocLink.ShareType = getConstantValue('HEP_SHARE_TYPE_V');
        insert objContentDocLink;
    }
        
    /**
    * Helps in Returning the value of a constant
    * @param sName -- name of the constant
    * @return value of the constant
    * @authod Sachin Agarwal
    */
    public static String getConstantValue(String sName){
        HEP_Constants__c objConstant = HEP_Constants__c.getValues(sName);
        
        if(objConstant != null){
            return objConstant.Value__c;
        }
        return null;
    }
    
    
    /**
    * AccessTokenWrapper --- wrapper for accesstoken for integrations
    * @author    Tejaswini Veliventi
    */
    public class AccessTokenWrapper { 
        public String access_token; 
        public String token_type;
        public String sandbox_url;
        public String service_url; 
        public String expires_in;
        public String errorCode;
        public String error;
    }
    /************************************************************************************************************************
  Method Name : sendToEDF
  Description : Utility method to send the constructed JSON to EDF for all Localization outbound integrations with EDF
  Parameter   : String sJSON - request body to be sent in web-service
                String integName - Custom setting record name to be used for Endpoints and Credentials
  Return type : String - Integration status
  *************************************************************************************************************************/
    public static String sendToEDF(String sJSON, String integName, Boolean retryFlag){
        String response = '';
        //make the callout to EDF
        try{
            if(FOX_Org_Sandbox_Control__c.getValues('LOC').Is_Sandbox__c){
                integName = integName + '_QA';
            }
            system.debug('integName====>'+integName);
            String access_token = retrieve_SOA_OAuth(integName);
            
            if(access_token==null){
                //insert business exception
                response = 'EDF Authentication Issue';
                String sId = LOC_Error_Log.BusinessException('EDF Authentication Issue', 'Integration Outbound',
                       'Outbound Response Status Error', 'Refer to attachments', 'LOC_Integration_Util',
                       'sendToEDF', '', '');
                LOC_Error_Log.InsertAttachment(sId, 'Outbound_Request', sJSON);

                //inserting record for retry in case retry flag is true
                if(retryFlag){
                    createInterfaceRetryRecord(integName, sJSON, 'EDF', response);
                }

                return response;
            }

            LOC_Authentication__c EDFservice= LOC_Authentication__c.getValues(integName); 
            String endpoint = EDFservice.Endpoint_URL__c;

            HttpRequest req = new HttpRequest();         
            req.setMethod('POST');
            
            // Set HTTPRequest header properties
            req.setHeader('Content-type', 'application/json');  
            req.setHeader('Authorization', access_token);
            req.setHeader('Accept', 'application/json');
            req.setTimeout(100000);
            req.setEndpoint(endpoint); 
            req.setBody(sJSON);    
            Http http = new Http();
            System.debug('####Endpoint:' + endpoint);
            System.debug('####sJSON:' + sJSON);

            //Execute web service call here     
            HTTPResponse res = http.send(req);      

            System.debug('EDF Response:'+res);
            if(res.getStatusCode()>=200 && res.getStatusCode()<300)
            {
                //transaction successful
                response = System.Label.LOC_Integ_Success;
            }
            else{
                //insert business exception
                response = 'Error connecting to EDF';
                String sId = LOC_Error_Log.BusinessException('EDF Callout Exception', 'Integration Outbound',
                       'Outbound Response Status Error', 'Refer to attachments', 'LOC_Integration_Util',
                       'sendToEDF', '', '');
                LOC_Error_Log.InsertAttachment(sId, 'Outbound_Request', sJSON);
                LOC_Error_Log.InsertAttachment(sId, 'Outbound_Response', res.getBody());

                //inserting record for retry in case retry flag is true
                if(retryFlag){
                    createInterfaceRetryRecord(integName, sJSON, 'EDF', res.getBody());
                }
            }
        }
        catch(Exception e){
            system.debug('In catch block:'+e.getMessage()+e.getLineNumber());
            LOC_Error_Log.genericException('LOC_Integration_Utility Exception', 'Integration Outbound', e,
                   'LOC_Integration_Util' , 'sendToEDF', '', '');
            response = e.getMessage();

            //inserting record for retry in case retry flag is true
            if(retryFlag){
                createInterfaceRetryRecord(integName, sJSON, 'EDF', response);
            }
        }
        return response;
    }
 /**********************************************************************************************************************************************
     * Name              : retrieve_SOA_OAuth
     * Description       : Retrieves the OAuth Token for the HTTP callouts to SOA.
     * Input Parameters  : outhEndPointCustomSetting - Name of custome Setting record which stores the Details of OAuth end point.
     * Return            : Token type and Access token
     **********************************************************************************************************************************************/
    public static String retrieve_SOA_OAuth(String integName) {
        String access_token = '';
        String type = '';
        HttpResponse res;
        String endpoint;
        String body;
        String status;
        String result;
        Transactionresponse Resp;
        HttpRequest SOAReq = new HttpRequest();
        //Sends the webservice request
        try {
            system.debug('integName====>'+integName);
            LOC_Authentication__c integDetails;
            integDetails = LOC_Authentication__c.getValues(integName);
            endpoint = integDetails.OAuth_Endpoint_URL__c;
            system.debug('endpoint'+integDetails);
            body = 'grant_type=' + integDetails.Service_Account_ID__c + '&client_id=' + integDetails.Share_Key_ID__c + '&client_secret=' + integDetails.Shared_Secret__c;

            System.debug('SOA OAUTH WEB SERVICE URL:' + endpoint);
            System.debug('SOA OAUTH WEB SERVICE BODY:' + body);
            SOAReq.setTimeout(20000);
            SOAReq.setEndpoint(endpoint);
            SOAReq.setMethod('POST');
            SOAReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            SOAReq.setBody(body);
            System.debug('SOA request:' + SOAReq.toString());
            Http h = new Http();
            res = h.send(SOAReq);

            System.debug('response SOA:' + res);
            result = res.getbody();
            System.debug('SOA WEB SERVICE RESPONSE:' + result);
            status = res.getStatus();
            
            if (status.equals('OK')) {
                Resp = (Transactionresponse) JSON.deserialize(result, Transactionresponse.class);
            } 
            else {
                LOC_Error_Log.BusinessException('SOA Service Error', 'Integration Outbound',
                                                 status, '', 'LOC_Integration_Util', 'retrieveOAuth', '', '');
                return null;
            }
        } 
        catch (Exception e) {
            status = e.getMessage();
            System.debug('status ==' + status+e.getLineNumber());
            LOC_Error_Log.genericException('SOA Outbound Exception', 'Integration Outbound', e,
                                            'LOC_Integration_Util' , 'retrieveOAuth', '', '');
            return null;
        }
        return Resp.token_type + ' ' + Resp.access_token;
    }
 /************************************************************************************************************************
  Method Name : createInterfaceRetryRecord
  Description : Utility method to create the Interface Transaction records which will be used for Retry
  Parameter   : String integBody - request body to be sent in the retry web-service
                String integName - Custom setting record name to be used for Endpoints and Credentials
                String integType - POST/GET
                String failureReason -  Error which has occured
  Return type : void
  *************************************************************************************************************************/
    public static void createInterfaceRetryRecord(String integName, String integBody, String integType, String failureReason){

        LOC_Interface_Retry_Tracker__c intRec = new LOC_Interface_Retry_Tracker__c();
        intRec.Interface_Name__c = integName;
        intRec.Interface_Type__c = integType;
        intRec.Request_Body__c = integBody;
        intRec.Retry_Counter__c = 1;
        intRec.Is_Success__c = false;
        intRec.Failure_Reason__c = failureReason;

        Database.insert(intRec);

        LOC_Error_Log.InsertAttachment(intRec.Id, 'Request Body', integBody);
    }
   //Below Class handles the response structure for OAuth
    public class Transactionresponse {
        public String access_token, token_type, expires_in;
        public Transactionresponse(String access_token, String token_type, String expires_in) {
            this.access_token = access_token;
            this.token_type = token_type;
            this.expires_in = expires_in;
        }
    } 

    /**
    * Retrieves the OAuth Token for the HTTP callouts 
    * @param    sServiceName- Name of custome Setting record which stores the Details of OAuth end point.
    * @return   Token type and Access token
    */
    public static map<String,String> retriveCatalogComponents(set<String> setCatIds) {

        string HEP_SELECTEDTITLES = HEP_Utility.getConstantValue('HEP_SELECTEDTITLES'); 
        string sCatalogComponents;
        list<string> lstComponents;
        string sComponents;
        string sCatId;
        List<CatalogCoupleComponentWrapper> lstCatalogCoupleComponentWrapper;
        map<String,String> mapCatIdVsComponents = new map<String,String>();
        if(setCatIds != null){
            for(string sCatalogId : setCatIds){
                sCatId = (Id)sCatalogId;
                sCatalogComponents = HEP_Integration_Util.retriveDatafromContent(sCatId, HEP_SELECTEDTITLES);
                if(!string.isBlank(sCatalogComponents)){
                    lstCatalogCoupleComponentWrapper =(list<CatalogCoupleComponentWrapper>) System.JSON.deserialize(sCatalogComponents, list<CatalogCoupleComponentWrapper>.class);
                    if(lstCatalogCoupleComponentWrapper != null && !lstCatalogCoupleComponentWrapper.isEmpty()){
                        lstComponents = new list<string>();
                        for(CatalogCoupleComponentWrapper objCatalogCoupleComponentWrapper : lstCatalogCoupleComponentWrapper){
                            lstComponents.add(objCatalogCoupleComponentWrapper.sFinancialTitleId);
                        }
                    }
                    if(lstComponents != null && !lstComponents.isEmpty())
                        sComponents = string.join(lstComponents,',');
                    else   
                        sComponents = ''; 
                }else{
                    sComponents = ''; 
                }   
                mapCatIdVsComponents.put(sCatalogId, sComponents);
            }       
        }
        return mapCatIdVsComponents;
    }   



    /**
    * DateType --- Wrapper class for Catalog components for TV Coupling(Episodes)
    * @author    Abhishek Mishra
    */
    public class CatalogCoupleComponentWrapper {    
        public String sFinancialTitleId;
        public String sFinancialTitleName;
        public String sInitialUSAirDate;
        public String sTitle;
        public String sTitleType;

        public CatalogCoupleComponentWrapper(String sFinancialTitleId, String sFinancialTitleName, String sInitialUSAirDate, String sTitle, String sTitleType){
            this.sFinancialTitleId = sFinancialTitleId;
            this.sFinancialTitleName = sFinancialTitleName;
            this.sInitialUSAirDate = sInitialUSAirDate;
            this.sTitle = sTitle;
            this.sTitleType = sTitleType;
        }
    }       
}