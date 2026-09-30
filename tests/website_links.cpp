#include <cassert>
#include <cwchar>
#include <iostream>
#include <limits>
#include "../native/WebsiteLinks.h"

int main(){
    const wchar_t* expected[]={
        L"https://github.com/mu-arch/SaureksCloset",
        L"https://github.com/mu-arch/SaureksCloset/releases",
        L"https://discord.gg/6mfxCdNbM6",
        L"https://ko-fi.com/comfysystems",
        L"https://cash.app/$saurek",
    };
    for(int i=0;i<5;++i){
        const wchar_t* url=allowedWebsite(i+1);
        assert(url&&std::wcscmp(url,expected[i])==0);
    }
    const double invalid[]={
        -1,0,6,100,1.5,3.999,4.5,5.001,
        std::numeric_limits<double>::quiet_NaN(),
        std::numeric_limits<double>::infinity(),
        -std::numeric_limits<double>::infinity(),
    };
    for(double page:invalid)assert(allowedWebsite(page)==nullptr);
    std::cout<<"PASS: existing and donation website allowlist, invalid page rejection\n";
}
