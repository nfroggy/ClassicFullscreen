/* Read-only: locate this Finder code image in a live Classic process. Prints
 * code addresses only. Used to translate FILE-relative diagnostic offsets. */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
    task_t task;FILE *f;unsigned char pattern[64],*bytes=malloc(1048576);
    vm_address_t addr=0;int found=0;
    if(argc!=3||!bytes||task_for_pid(mach_task_self(),atoi(argv[1]),&task))return 1;
    f=fopen(argv[2],"rb");if(!f)return 1;fseek(f,0xb070,SEEK_SET);
    if(fread(pattern,1,sizeof(pattern),f)!=sizeof(pattern))return 1;fclose(f);
    while(addr<0x40000000) {
        vm_size_t size;vm_region_basic_info_data_t info;
        mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT;mach_port_t object;
        if(vm_region(task,&addr,&size,VM_REGION_BASIC_INFO,(vm_region_info_t)&info,&count,&object))break;
        if(object)mach_port_deallocate(mach_task_self(),object);
        if((info.protection&VM_PROT_READ)&&addr<0x40000000) {
            vm_address_t pos;
            for(pos=addr;pos<addr+size;pos+=1048512) {
                vm_size_t n=addr+size-pos,got=0;unsigned i;
                if(n>1048576)n=1048576;
                if(vm_read_overwrite(task,pos,n,(vm_address_t)bytes,&got)||got!=n)continue;
                for(i=0;i+sizeof(pattern)<=n;i+=4) if(!memcmp(bytes+i,pattern,sizeof(pattern))) {
                    printf("Finder FILE-offset base=%08lx\n",(unsigned long)(pos+i-0xb070));found++;
                }
            }
        }
        if(!size||addr+size<addr)break;addr+=size;
    }
    mach_port_deallocate(mach_task_self(),task);free(bytes);return found==1?0:1;
}
