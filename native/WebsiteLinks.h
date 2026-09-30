#pragma once

// Exact, compiled page IDs only: neither update responses nor callers can
// supply an arbitrary URL, and fractional/non-finite IDs cannot match.
static inline const wchar_t* allowedWebsite(double page){
    if(page==1)return L"https://github.com/mu-arch/SaureksCloset";
    if(page==2)return L"https://github.com/mu-arch/SaureksCloset/releases";
    if(page==3)return L"https://discord.gg/6mfxCdNbM6";
    if(page==4)return L"https://ko-fi.com/comfysystems";
    if(page==5)return L"https://cash.app/$saurek";
    return nullptr;
}
