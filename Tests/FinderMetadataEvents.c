/* Visible integration-test helper. Sends AppleEvents only to the running OS 9
 * Finder identified by its exact executable path, never the OS X Finder.
 * Usage: helper SYSTEM_FOLDER/Finder open|close PATH
 *        helper SYSTEM_FOLDER/Finder get PATH FOURCC
 *        helper SYSTEM_FOLDER/Finder set PATH FOURCC point X Y|long N|text S
 *        helper SYSTEM_FOLDER/Finder set PATH FOURCC rect TOP LEFT BOTTOM RIGHT
 * Uses disposable fixtures for setters. The alias can also be read after a
 * Classic restart, so assertions don't just observe Finder's in-memory cache. */
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void need(OSStatus err,const char *why) {
    if(err) {fprintf(stderr,"%s: %ld\n",why,(long)err);exit(1);}
}
int main(int argc,char **argv) {
    ProcessSerialNumber psn={0,kNoProcess}; FSRef ref; AliasHandle alias=NULL;
    AEAddressDesc target={typeNull,NULL}; AEDesc object={typeNull,NULL}, documents={typeNull,NULL};
    AEDesc prop={typeNull,NULL},key={typeNull,NULL};
    AppleEvent event={typeNull,NULL},reply={typeNull,NULL};
    OSType code,resultType; Size actual; OSStatus err; SInt32 remote=0;
    int get,set,window; unsigned char data[1024];
    if(argc<4) return 2;
    window=!strcmp(argv[2],"getwin")||!strcmp(argv[2],"setwin");
    get=!strcmp(argv[2],"get")||!strcmp(argv[2],"getwin");
    set=!strcmp(argv[2],"set")||!strcmp(argv[2],"setwin");
    if((get||set)&&(argc<5||strlen(argv[4])!=4)) return 2;
    if(!get&&!set&&strcmp(argv[2],"open")&&strcmp(argv[2],"close")) return 2;
    while(GetNextProcess(&psn)==noErr) {
        ProcessInfoRec info; FSSpec spec; UInt8 path[1024];
        memset(&info,0,sizeof(info));info.processInfoLength=sizeof(info);info.processAppSpec=&spec;
        if(!GetProcessInformation(&psn,&info)&&info.processSignature=='MACS'&&
           info.processType=='FNDR'&&!FSpMakeFSRef(&spec,&ref)&&
           !FSRefMakePath(&ref,path,sizeof(path))&&!strcmp((char *)path,argv[1])) break;
    }
    if(psn.lowLongOfPSN==kNoProcess) {fputs("OS 9 Finder not running\n",stderr);return 1;}
    need(AECreateDesc(typeProcessSerialNumber,&psn,sizeof(psn),&target),"target");
    need(FSPathMakeRef((UInt8 *)argv[3],&ref,NULL),"fixture ref");
    need(FSNewAliasMinimal(&ref,&alias),"alias");HLock((Handle)alias);
    need(AECreateDesc(typeAlias,*alias,GetHandleSize((Handle)alias),&object),"alias descriptor");
    DisposeHandle((Handle)alias);
    if(window) {
        AEDesc itemWindow={typeNull,NULL}; code='cwin';
        need(AECreateDesc(typeType,&code,4,&key),"window property code");
        need(CreateObjSpecifier(cProperty,&object,formPropertyID,&key,false,&itemWindow),"item window");
        AEDisposeDesc(&object);AEDisposeDesc(&key);object=itemWindow;
    }
    if(get||set) {
        memcpy(&code,argv[4],4);need(AECreateDesc(typeType,&code,4,&key),"property code");
        need(CreateObjSpecifier(cProperty,&object,formPropertyID,&key,false,&prop),"property");
    }
    need(AECreateAppleEvent(!strcmp(argv[2],"open")?kCoreEventClass:kAECoreSuite,
         get?kAEGetData:set?kAESetData:!strcmp(argv[2],"open")?kAEOpenDocuments:kAEClose,
         &target,kAutoGenerateReturnID,kAnyTransactionID,&event),"event");
    if(!strcmp(argv[2],"open")) {
        need(AECreateList(NULL,0,false,&documents),"document list");
        need(AEPutDesc(&documents,0,&object),"document alias");
    }
    need(AEPutParamDesc(&event,keyDirectObject,get||set?&prop:
         !strcmp(argv[2],"open")?&documents:&object),"direct object");
    if(set) {
        if(argc>=8&&!strcmp(argv[5],"point")) {
            Point p;p.h=atoi(argv[6]);p.v=atoi(argv[7]);
            need(AEPutParamPtr(&event,keyAEData,typeQDPoint,&p,sizeof(p)),"point");
        } else if(argc>=10&&!strcmp(argv[5],"rect")) {
            Rect r;r.top=atoi(argv[6]);r.left=atoi(argv[7]);r.bottom=atoi(argv[8]);r.right=atoi(argv[9]);
            need(AEPutParamPtr(&event,keyAEData,typeQDRectangle,&r,sizeof(r)),"rectangle");
        } else if(argc>=7&&!strcmp(argv[5],"long")) {
            SInt32 v=atoi(argv[6]);need(AEPutParamPtr(&event,keyAEData,typeSInt32,&v,4),"integer");
        } else if(argc>=7&&!strcmp(argv[5],"enum")&&strlen(argv[6])==4) {
            need(AEPutParamPtr(&event,keyAEData,typeEnumerated,argv[6],4),"enumeration");
        } else if(argc>=7&&!strcmp(argv[5],"text")) {
            need(AEPutParamPtr(&event,keyAEData,typeChar,argv[6],strlen(argv[6])),"text");
        } else return 2;
    }
    need(AESendMessage(&event,&reply,kAEWaitReply|kAENeverInteract,300),"send");
    err=AEGetParamPtr(&reply,keyErrorNumber,typeSInt32,&resultType,&remote,sizeof(remote),&actual);
    if(err!=errAEDescNotFound) need(err,"error result");
    if(remote) {
        Size length=0;DescType type;
        if(!AEGetParamPtr(&reply,keyErrorString,typeChar,&type,data,sizeof(data)-1,&length)) {
            data[length]=0;fprintf(stderr,"Finder: %s\n",data);
        }
    }
    need(remote,"Finder response");
    if(get) {
        int i;need(AEGetParamPtr(&reply,keyDirectObject,typeWildCard,&resultType,data,sizeof(data),&actual),"value");
        printf("%.4s:",(char *)&resultType);
        for(i=0;i<actual;i++) printf("%02x",data[i]); puts("");
    } else puts("OK");
    return 0;
}
