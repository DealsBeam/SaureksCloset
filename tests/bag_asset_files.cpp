#include <cassert>
#include <cstring>
#include <initializer_list>
#include <iostream>
#include <string>
#define __fastcall
static constexpr unsigned INVALID_FILE_ATTRIBUTES=~0u,FILE_ATTRIBUTE_DIRECTORY=16;
static unsigned attributes=0,calls=0;
static unsigned GetFileAttributesA(const char*){return attributes;}
#include "../native/BagAssetFiles.h"
static int fallback(const char*,char*,unsigned,unsigned,unsigned*,void**){++calls;return 7;}
int main(){
    resolveAssetFileOriginal=fallback;
    char output[260]{};unsigned kind=99;void* archive=reinterpret_cast<void*>(123);
    assert(bagCatalogCount==16&&!bagAsset(0)&&!bagAsset(17));
    unsigned id=0;
    for(const auto& bag:bagCatalog){
        assert(bag.id==++id&&bagAsset(id)==&bag&&bagCatalogFind(id)==&bag);
        assert(bag.name&&bag.name[0]&&std::strstr(bag.model,".mdx"));
        assert(bagAssetFile(bag.texture));
    }
    for(const char* input:bagAssetFiles){
        assert(resolveAssetFileHook(input,output,sizeof(output),0,&kind,&archive)==1);
        assert(kind==0&&!archive&&!calls&&std::strcmp(output,input)==0);
        std::string normalized=input;
        for(auto& c:normalized){if(c=='\\')c='/';else if(c>='A'&&c<='Z')c+=32;}
        assert(std::strcmp(bagAssetFile(normalized.c_str()),input)==0);
        assert(!bagAssetFile((std::string(input)+".bak").c_str()));
    }
    for(const char* input:{"Interface\\AddOns\\SaureksCloset\\Models\\DarkSchoolbag.m2","interface/addons/saurekscloset/models/darkschoolbag.blp"}){
        assert(resolveAssetFileHook(input,output,sizeof(output),0,&kind,&archive)==1);
        assert(kind==0&&!archive&&!calls&&std::strcmp(output,bagAssetFile(input))==0);
    }
    for(const char* input:{"Item\\ObjectComponents\\Quiver\\Quiver_A.m2","Interface\\AddOns\\Other\\DarkSchoolbag.m2","Interface\\AddOns\\SaureksCloset\\Models\\..\\DarkSchoolbag.m2","Interface\\AddOns\\SaureksCloset\\Models\\DarkSchoolbag.m2.bak","",static_cast<const char*>(nullptr)}){
        assert(!bagAssetFile(input));assert(resolveAssetFileHook(input,output,sizeof(output),0,&kind,&archive)==7);
    }
    auto* path="Interface\\AddOns\\SaureksCloset\\Models\\DarkSchoolbag.m2";
    for(auto invalid:{INVALID_FILE_ATTRIBUTES,FILE_ATTRIBUTE_DIRECTORY}){attributes=invalid;assert(resolveAssetFileHook(path,output,sizeof(output),0,&kind,&archive)==7);}
    attributes=0;output[0]='!';assert(resolveAssetFileHook(path,output,2,0,&kind,&archive)==7&&output[0]=='!');
    assert(resolveAssetFileHook(path,nullptr,260,0,&kind,&archive)==7);
    assert(resolveAssetFileHook(path,output,260,0,nullptr,&archive)==7);
    std::cout<<"PASS: all 32 catalog assets use client disk handles; missing files, short buffers and all other paths retain original lookup\n";
}
