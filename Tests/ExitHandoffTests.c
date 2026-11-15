/* Runs the installed candidate's exact PPC bytes in an isolated process.
 * Imports are mocks; this does not attach to Classic or use process services.
 * Poison the dying PEntry before the late hook to catch lifetime mistakes.
 */
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int U;
#define BASE 0x30000000U
static unsigned char toc_store[0x4000],dying[256],next[256],flags[2];
static unsigned char *toc=toc_store+0x800;
static U state[8],old_psn[2]={7,0x12340001},front[2],selected[2];
static unsigned char layers[5][256],special[32],host_next[256];
static int native_query;
static void *host_result;
static void *published,*special_ptr,*queued,*special_result,*visible_layer,*any_layer;
static int queue_calls,lookup_calls,layer_calls,window_calls,sub_calls,ipc_calls;
static int get_error,set_error,events[8],count;
static U *word(void *p,U n){return (U*)((char*)p+n);}
static void check(int ok,const char *msg){if(!ok){fprintf(stderr,"FAIL: %s\n",msg);exit(1);}}
static void event(int n){check(count<8,"event bound");events[count++]=n;}
static void locks(void){check(state[4]==0,"break locks before cleanup");event(1);}
static void cleanup(void *entry,int error,int no_layers){check(entry==dying&&error==-42&&!no_layers,"cleanup arguments");check(state[4]==0,"cleanup before selection");event(2);}
static void tmkill(void){event(3);}
static int get_front(U *p){check(state[4]==1,"front query after selection");event(4);p[0]=front[0];p[1]=front[1];return get_error;}
static int set_front(U *p){check(p==word(next,0x24),"activate actual successor PSN");check(state[4]==1,"activation after selection");event(5);selected[0]=p[0];selected[1]=p[1];return set_error;}
static int died(U *p,U was_front,int error){check(state[4]==1,"unregister after selection");check(p[0]==old_psn[0]&&p[1]==old_psn[1],"copied PSN survives freed entry");check(was_front==state[1]&&error==-42,"death arguments unchanged");event(6);return 0;}
static void *pop(void){queue_calls++;return queued;}
static void *lookup(void *p){
 lookup_calls++;
 if(native_query){check(!memcmp(p,front,8),"native exit resolves the host's current PSN");return host_result;}
 check(p==special+16,"special PSN argument");return special_result;
}
static void *layer_windows(void *p){check(!p,"layer search starts at front");window_calls++;return visible_layer;}
static void *layer_next(void *p,int visible){check(!p,"basic layer starts at front");layer_calls++;return visible?visible_layer:any_layer;}
static void *subwindows(void *p){check(p==(void*)0x1234,"application layer root");sub_calls++;return layers[0];}
static void ipc(void){check(state[4]==1,"IPC after cleanup");ipc_calls++;if(flags[0]&&flags[1]&&!native_query)check(count&&events[count-1]==6,"death before nonlocal IPC return");}
static void put(U a,U v){*(U*)(BASE+a)=v;}
static void jump(U a,U target){put(a,0x48000000|((target-a)&0x03fffffc));}
static void stub(U a,void *fn,int cfm){
 U v=(U)fn;
 if(cfm){put(a,0x90410014);put(a+4,0x3c40dead);a+=8;}
 else {put(a,0x7c0802a6);put(a+4,0x90010008);put(a+8,0x9421ffc0);put(a+12,0x90410038);a+=16;}
 put(a,0x3d800000|(v>>16));put(a+4,0x618c0000|(v&65535));put(a+8,0x7d8903a6);
 if(cfm)put(a+12,0x4e800420);
 else {put(a+12,0x4e800421);put(a+16,0x80410038);put(a+20,0x38210040);put(a+24,0x80010008);put(a+28,0x7c0803a6);put(a+32,0x4e800020);}
}
extern void sys_icache_invalidate(void*,unsigned long);
static void load_entry(const char *path) {
 FILE *f=fopen(path,"rb");struct mach_header header;U offset=sizeof(header),i,j,found=0;
 check(f!=NULL,"open entry object");
 check(fread(&header,1,sizeof(header),f)==sizeof(header)&&header.magic==MH_MAGIC&&
       header.cputype==CPU_TYPE_POWERPC&&header.filetype==MH_OBJECT&&header.ncmds<128,"PPC entry object");
 for(i=0;i<header.ncmds;i++){
  struct load_command command;
  check(!fseek(f,offset,SEEK_SET)&&fread(&command,1,sizeof(command),f)==sizeof(command),"entry load command");
  if(command.cmd==LC_SEGMENT){
   struct segment_command segment;
   check(!fseek(f,offset,SEEK_SET)&&fread(&segment,1,sizeof(segment),f)==sizeof(segment)&&segment.nsects<128,"entry segment");
   for(j=0;j<segment.nsects;j++){
    struct section s;
    check(fread(&s,1,sizeof(s),f)==sizeof(s),"entry section");
    if(!strncmp(s.sectname,"__text",16)){
     check(!s.addr&&s.size>=0x51120&&!s.nreloc,"resolved entry text");found=s.offset;
    }
   }
  }
  check(command.cmdsize>=sizeof(command),"entry command length");offset+=command.cmdsize;
 }
 check(found&&!fseek(f,found+0x51000,SEEK_SET)&&
       fread((void*)(BASE+0x51000),1,0x120,f)==0x120,"read entry code");fclose(f);
}
int main(int argc,char **argv){
 FILE *f;vm_address_t address=BASE;int enabled,native,fg,target,which,err,serr,checks=0,expected[8],n,i,valid;
 void (*run)(void*,void*);
 check(argc==3,"candidate guest and assembled test-entry object required");
 check(!vm_allocate(mach_task_self(),&address,0x60000,0)&&address==BASE,"map test image");
 f=fopen(argv[1],"rb");check(f!=NULL,"open guest");check(fread((void*)BASE,1,0x50000,f)==0x50000,"read guest");fclose(f);
 load_entry(argv[2]);
 stub(0x4d5c4,locks,1);stub(0x2e304,cleanup,0);stub(0x2ed8c,tmkill,0);
 stub(0x4d42c,get_front,1);stub(0x4d984,set_front,1);stub(0x4e224,died,1);
 stub(0x3d184,pop,0);stub(0x2fc54,lookup,0);stub(0x26ef4,layer_windows,0);
 stub(0x4cb74,layer_next,1);stub(0x4d5dc,subwindows,1);stub(0x3736c,ipc,0);
 jump(0x2f758,0x51080);jump(0x2fa28,0x51100);
 sys_icache_invalidate((void*)BASE,0x60000);run=(void*)(BASE+0x51000);
 *word(toc,-0x30c)=(U)&flags[0];*word(toc,-0x1a8)=(U)&flags[1];
 for(enabled=0;enabled<4;enabled++)for(native=0;native<2;native++)
 for(fg=0;fg<2;fg++)for(target=0;target<3;target++)for(which=0;which<3;which++)
 for(err=0;err<2;err++)for(serr=0;serr<2;serr++){
  flags[0]=(enabled&1)?1:0;flags[1]=(enabled&2)?1:0;
  *word(dying,0x3c)=native?0x01000000:0;*word(dying,0x24)=old_psn[0];*word(dying,0x28)=old_psn[1];
  *word(next,0x24)=0;*word(next,0x28)=0x43210001;*word(next,0x3c)=target==2?0x01000000:0;
  state[0]=(U)dying;state[1]=fg;state[2]=-42;state[3]=target?(U)next:0;
  front[0]=old_psn[0]+(which==1);front[1]=old_psn[1]+(which==2);
  count=0;get_error=err?-50:0;set_error=serr?-50:0;selected[0]=selected[1]=0;
  run(state,toc);n=0;valid=enabled==3&&!native;
  if(valid)expected[n++]=1;expected[n++]=2;expected[n++]=3;
  if(valid){if(fg&&target){expected[n++]=4;if(!err&&!which)expected[n++]=5;}expected[n++]=6;}
  check(count==n,"event count");for(i=0;i<n;i++)check(events[i]==expected[i],"call order");
  if(state[5]!=(U)(toc+0x7c8)||state[6]!=(U)toc)fprintf(stderr,"case %d %d %d %d %d %d %d r12=%08x r2=%08x toc=%08x\n",enabled,native,fg,target,which,err,serr,state[5],state[6],(U)toc);
  check(state[5]==(U)(toc+0x7c8)&&state[6]==(U)toc,"original instruction and TOC restored");
  if(valid&&fg&&target&&!err&&!which)check(selected[1]==0x43210001,"selected app is successor, not Finder");
  else check(!selected[0]&&!selected[1],"no activation for away/background/invalid cases");
  checks++;
 }
 /* Exercise each unchanged priority source and the new native-layer fallback. */
 *word(toc,-0x2fc)=(U)&published;*word(toc,-0x2a8)=(U)&special_ptr;
 *word(toc,0x297c)=0x1234;
 for(target=0;target<2;target++)for(which=0;which<6;which++)for(fg=0;fg<2;fg++){
  flags[0]=flags[1]=1;*word(dying,0x3c)=0;*word(dying,0x24)=old_psn[0];*word(dying,0x28)=old_psn[1];
  *word(next,0x3c)=target?0x01000000:0;
  state[0]=(U)dying;state[1]=fg;state[2]=-42;state[3]=(U)next;state[7]=1;
  front[0]=old_psn[0]+1;get_error=set_error=0;count=0;
  queue_calls=lookup_calls=layer_calls=window_calls=sub_calls=0;
  published=(void*)0x7777;*word(toc,0x295c)=which==0?(U)next:0;
  queued=which==1?next:NULL;special_ptr=which==2?special:NULL;special_result=next;
  toc[0x7a8]=which==3;visible_layer=which==5?NULL:layers[4];any_layer=layers[4];
  for(i=0;i<5;i++){memset(layers[i],0,256);*word(layers[i],0x90)=i<4?(U)layers[i+1]:0;layers[i][0x6e]=1;}
  *word(layers[0],0x98)=(U)next; /* native or existing guest */
  *word(layers[1],0x98)=0; /* no owner */
  *word(layers[2],0x98)=(U)dying;layers[2][0x6e]=0; /* hidden guest */
  *word(layers[3],0x98)=(U)dying; /* visible guest fallback */
  *word(layers[4],0x98)=(U)next;
  run(state,toc);
  if(!fg){check(published==(void*)0x7777&&!queue_calls&&!lookup_calls&&!layer_calls&&!window_calls&&!sub_calls,"background exit leaves guest selection alone");}
  else {
   check(published==(target?(void*)dying:(void*)next),"priority and native fallback selection");
   check(queue_calls==(which>0)&&lookup_calls==(which==2),"pending/queue/special precedence");
   check(window_calls==(which==3)&&layer_calls==(which==4?1:which==5?2:0),"original layer search paths");
   check(sub_calls==target,"native fallback only for native candidate");
  }
  checks++;
 }
 /* IPC cleanup can escape before normal selection. If it returns, notify once. */
 for(enabled=0;enabled<2;enabled++){
  flags[0]=flags[1]=enabled;*word(dying,0x3c)=0;*word(dying,0x24)=old_psn[0];*word(dying,0x28)=old_psn[1];
  state[0]=(U)dying;state[1]=0;state[2]=-42;state[3]=0;state[7]=2;count=0;ipc_calls=0;
  run(state,toc);check(ipc_calls==1,"original IPC handler called");
  check(count==(enabled?4:2),"IPC death notification occurs exactly once");checks++;
 }
 /* A dying native proxy must not activate the guest behind it. Follow the
  * host's current native OR guest app; a background proxy changes nothing.
  * Also exercise the IPC return and failed-query/missing-process fallbacks. */
 native_query=1;
 for(which=1;which<=2;which++)for(fg=0;fg<2;fg++)for(target=0;target<4;target++){
  flags[0]=flags[1]=1;*word(dying,0x3c)=0x01000000;
  *word(dying,0x24)=old_psn[0];*word(dying,0x28)=old_psn[1];
  *word(next,0x3c)=0;*word(host_next,0x3c)=target==1?0:0x01000000;
  *word(host_next,0x24)=0;*word(host_next,0x28)=0x98760001;
  state[0]=(U)dying;state[1]=fg;state[2]=-42;state[3]=(U)next;state[7]=which;
  front[0]=0;front[1]=0x98760001;get_error=target==3?-50:0;host_result=target==2?NULL:host_next;
  count=0;ipc_calls=lookup_calls=queue_calls=layer_calls=window_calls=sub_calls=0;
  selected[0]=selected[1]=0;published=(void*)0x7777;*word(toc,0x295c)=(U)next;
  run(state,toc);
  check(!selected[0]&&!selected[1],"native cleanup must not request activation");
  if(!fg){
   check(published==(void*)0x7777&&count==2&&!lookup_calls,"background native exit preserves Classic or OS X focus");
  }else{
   check(published==(target<2?(void*)host_next:(void*)next),"native exit follows actual host foreground instead of guest fallback");
   check(count==3&&events[0]==2&&events[1]==3&&events[2]==4,"native exit queries focus without guest activation/death notification");
   check(lookup_calls==(target!=3),"failed native foreground query skips lookup");
  }
  check(ipc_calls==(which==2),"native IPC path retains original callback");
  check(state[5]==(U)(toc+0x7c8)&&state[6]==(U)toc,"native exit preserves registers and TOC");
  checks++;
 }
 printf("PASS: %d exact PPC exit scenarios; guest selection, native foreground preservation, background exits, freed process data, API failures, registers, TOC, IPC and call ordering.\n",checks);
 return 0;
}
