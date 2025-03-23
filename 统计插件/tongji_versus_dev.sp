#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>
#include <l4d_lib>
#include <readyup>

#define HITGROUP_HEAD 1
#define ZC_HUNTER  3

enum WeaponCategory
{
    WC_INVALID,
    WC_SHOTGUN,
    WC_FULLAUTO,
    WC_SEMIAUTO
};

enum ZombieClass
{
    ZC_Smoker = 1,
    ZC_Boomer = 2,
    ZC_Hunter = 3,
    ZC_Spitter = 4,
    ZC_Jockey = 5,
    ZC_Charger = 6,
    ZC_Tank = 8
};

// 玩家统计数据结构
int g_iShots[MAXPLAYERS + 1];
int g_iHits[MAXPLAYERS + 1];
int g_iHeadshots[MAXPLAYERS + 1];
int g_iShotgunMidairHunters[MAXPLAYERS + 1];
int g_iMeleeMidairHunters[MAXPLAYERS + 1];
int g_iSMGUnder10Kills[MAXPLAYERS + 1];
int g_iHunted[MAXPLAYERS + 1];
int g_iKilledSI[MAXPLAYERS + 1];
int g_iDamageSI[MAXPLAYERS + 1];
int g_iControlled[MAXPLAYERS + 1];
int g_iMissedShots[MAXPLAYERS + 1];
int g_iEffectiveHits[MAXPLAYERS + 1];
int g_iTankHits[MAXPLAYERS + 1];
int g_iTankRockHits[MAXPLAYERS + 1];
int iPounceDmgInt;

int g_iLastRoundShots[MAXPLAYERS + 1];
int g_iLastRoundHits[MAXPLAYERS + 1];
int g_iLastRoundHeadshots[MAXPLAYERS + 1];
int g_iLastRoundShotgunMidairHunters[MAXPLAYERS + 1];
int g_iLastRoundMeleeMidairHunters[MAXPLAYERS + 1];
int g_iLastRoundSMGUnder10Kills[MAXPLAYERS + 1];
int g_iLastRoundHunted[MAXPLAYERS + 1];
int g_iLastRoundKilledSI[MAXPLAYERS + 1];
int g_iLastRoundDamageSI[MAXPLAYERS + 1];
int g_iLastRoundControlled[MAXPLAYERS + 1];
int g_iLastRoundMissedShots[MAXPLAYERS + 1];
int g_iLastRoundEffectiveHits[MAXPLAYERS + 1];
int g_iLastRoundTankHits[MAXPLAYERS + 1];
int g_iLastRoundTankRockHits[MAXPLAYERS + 1];

//float g_fLastTongjiPrintTime[MAXPLAYERS + 1];

bool g_bCurrentShotHitRegistered[MAXPLAYERS + 1];
bool g_bShotgunHitRegistered[MAXPLAYERS + 1];
bool g_bShotHitRegistered[MAXPLAYERS + 1];
bool g_bShotgunHeadshotRegistered[MAXPLAYERS + 1];
bool bIsPouncing[MAXPLAYERS + 1];
bool bIsHurt[MAXPLAYERS + 1];
bool g_bSIDeathRegistered[MAXPLAYERS + 1];
bool g_bHasPrintedStats[MAXPLAYERS + 1];
bool g_bHasLoggedStats = false;
bool g_bIsRoundLive = false;

ConVar g_cvAutoPrintStats;

public Plugin myinfo = 
{
    name = "星云猫猫统计",
    author = "Seiunsky Maomao",
    description = "统计玩家对于特感的各种数据.",
    version = "dev-01",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    //挂钩
    //HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("weapon_fire", Event_WeaponFire);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("lunge_pounce", Event_HunterPounced);
    HookEvent("tongue_grab", Event_SmokerGrab);
    HookEvent("jockey_ride", Event_JockeyRide);
    HookEvent("charger_pummel_start", Event_ChargerPummel);
    //HookEvent("infected_hurt", Event_InfectedHurt);   //小僵尸受伤事件的,现在和witch事件丢一起了
    HookEvent("ability_use", AbilityUse_Event);
    HookEvent("player_death", PlayerDeath_Event);
    HookEvent("player_spawn", OnPlayerSpawn);
    
    RegConsoleCmd("sm_tongji", Command_Tongji, "查看上一回合的统计数据");
    RegConsoleCmd("sm_quanbutongji", Command_QuanbuTongji, "查看本人历史全部的统计数据");

    g_cvAutoPrintStats = CreateConVar("sm_tongji_zidong", "1", "是否在回合结束时自动打印统计信息 (1 = 开启, 0 = 关闭)", FCVAR_NONE, true, 0.0, true, 1.0);

    ConVar hPounceDmgInt = FindConVar("z_pounce_damage_interrupt");
    if (hPounceDmgInt != INVALID_HANDLE)
    {
        iPounceDmgInt = GetConVarInt(hPounceDmgInt);
    }
    else
    {
        iPounceDmgInt = 150; // 对抗模式默认值150，如果找不到就150
    }

    InitLogDirectory();
}

// 当回合正式开始，标记为激活状态
// 并且清除各种标记、记录
public void OnRoundIsLive()  // 移除参数，使其符合 readyup 插件的前向声明
{
    g_bIsRoundLive = true;
    g_bHasLoggedStats = false;
    
    // 为所有客户端重置统计数据
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ResetClientStats(client);
            g_bHasPrintedStats[client] = false;
        }
    }
    
    PrintToChatAll("\x01[!] \x03回合开始, 星云猫猫统计\x04已激活\x03.");
}

// 每回合重置玩家统计
void ResetClientStats(int client)
{
    g_iShots[client] = 0;
    g_iHits[client] = 0;
    g_iHeadshots[client] = 0;
    g_iShotgunMidairHunters[client] = 0;
    g_iMeleeMidairHunters[client] = 0;
    g_iSMGUnder10Kills[client] = 0;
    g_iHunted[client] = 0;
    g_iKilledSI[client] = 0;
    g_iDamageSI[client] = 0;
    g_iControlled[client] = 0;
    g_bShotgunHitRegistered[client] = false;
    g_bShotHitRegistered[client] = false;
    g_bShotgunHeadshotRegistered[client] = false;
    g_iMissedShots[client] = 0;
    g_iEffectiveHits[client] = 0;
    g_iTankHits[client] = 0;
    g_iTankRockHits[client] = 0;
    // 重置特感的击杀标记
    if (IsValidInfected(client))
    {
        g_bSIDeathRegistered[client] = false;
    }
}

/* 丢到OnRoundIsLive里
// 回合开始时重置统计数据和标志
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bIsRoundLive = false;     //readyup插件，回合开始时标记为未激活
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ResetClientStats(client);
            g_bHasPrintedStats[client] = false;
        }
    }
}
*/

// 初始化日志目录
void InitLogDirectory()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "logs/player");    //日志位置
    if (!DirExists(sPath))
    {
        CreateDirectory(sPath, 493);
    }
}

// 掉线的要清
public void OnClientDisconnect(int client)
{
    ResetClientStats(client);
    g_bHasPrintedStats[client] = false;
}

// 特感控制事件
// Hunter
public Action Event_HunterPounced(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if(IsValidHumanSurvivor(victim)) g_iHunted[victim]++;
    return Plugin_Continue;
}

// Smoker
public void Event_SmokerGrab(Event event, const char[] name, bool dontBroadcast)
{
    int victimUserId = event.GetInt("victim");
    HandleControl(victimUserId);
}

// Jockey
public void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast)
{
    HandleControl(event.GetInt("victim"));
}

// Charger
public void Event_ChargerPummel(Event event, const char[] name, bool dontBroadcast)
{
    HandleControl(event.GetInt("victim"));
}

void HandleControl(int userid)
{
    int client = GetClientOfUserId(userid);
    if(IsValidHumanSurvivor(client)) g_iControlled[client]++;
}

public Action Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
    return Plugin_Continue; // 以后没准有用
}

// 实体生成事件过滤处理，谢谢Hi提供的思路
// 注意，这个只能统计到ai实体
public void OnEntityCreated(int entity, const char[] classname)
{
    //其他命中
    if (StrEqual(classname, "witch") || StrEqual(classname, "infected"))
    {
        SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
    }
    // 过滤出克的饼
    else if (StrEqual(classname, "tank_rock"))
    {
        SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_TankRock);
    }
    // 过滤出克
    else if (StrEqual(classname, "tank"))
    {
        SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Tank);
    }
}

// 更新 bIsPouncing 和 bIsHurt 状态，给空爆统计
public Action AbilityUse_Event(Event event, const char[] name, bool dontBroadcast)
{
    int user = GetClientOfUserId(event.GetInt("userid"));
    char abilityName[64];
    GetEventString(event, "ability", abilityName, sizeof(abilityName));

    if (IsValidInfected(user) && view_as<ZombieClass>(GetEntProp(user, Prop_Send, "m_zombieClass")) == ZC_Hunter)
    {
        // 处理 Hunter 的飞扑状态
        if (StrEqual(abilityName, "ability_lunge", true) && !bIsPouncing[user])
        {
            bIsPouncing[user] = true;
            bIsHurt[user] = (GetClientHealth(user) < iPounceDmgInt);
            //PrintToChatAll("[DEBUG] Hunter [%N] 正在飞扑!", user);
        }
    }

    return Plugin_Continue;
}

// 现在吧对6只特感的击杀量（g_iKilledSI）转移到这里了，这里方便点
public Action PlayerDeath_Event(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bIsRoundLive) return Plugin_Continue;    // 回合没被宣布开始时，则关闭

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidHumanSurvivor(attacker) || !IsValidInfected(victim)) return Plugin_Continue;

    int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");

    // 伤害统计枪械+近战，hunter在多加分开统计
    if (!g_bSIDeathRegistered[victim])
    {
        if (IsFirearm(weapon) || IsMelee(weapon))
        {
            g_bSIDeathRegistered[victim] = true;
            g_iKilledSI[attacker]++;
            //PrintToChatAll("[DEBUG] %N 使用%s击杀了特感 [%N]!", attacker, IsMelee(weapon) ? "近战武器" : "枪械", victim);
        }

        // 在进行Hunter的空爆统计
        if (zClass == ZC_HUNTER)
        {
            int damagetype = event.GetInt("type");

            if (weapon == -1) return Plugin_Continue;

            // 获取武器类名
            char weaponClass[64];
            GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));

            // 获取武器类型
            int weaponType = L4D2_GetIntWeaponAttribute(weaponClass, L4D2IWA_WeaponType);

            // 判断是否为喷子、近战、机枪
            bool isShotgun = (weaponType == view_as<int>(WEAPONTYPE_SHOTGUN));
            bool isMelee = (weaponType == view_as<int>(WEAPONTYPE_MELEE));
            bool isSMG = (weaponType == view_as<int>(WEAPONTYPE_SMG));

            // 判断是否是飞扑2状态的hunter
            if (bIsPouncing[victim])
            {
                if (damagetype & DMG_BUCKSHOT || damagetype & DMG_BULLET || damagetype & DMG_SLASH || damagetype & DMG_CLUB)
                {
                    if (isShotgun)
                    {
                        // 喷子空爆
                        g_iShotgunMidairHunters[attacker]++;
                        //PrintToChatAll("[DEBUG] %N 使用霰弹枪空爆了 Hunter!", attacker);
                    }
                    else if (isMelee)
                    {
                        // 近战空爆
                        g_iMeleeMidairHunters[attacker]++;
                        //PrintToChatAll("[DEBUG] %N 使用近战武器空爆了 Hunter!", attacker);
                    }
                    else if (isSMG)
                    {
                        // 机枪空爆
                        g_iSMGUnder10Kills[attacker]++;
                        //PrintToChatAll("[DEBUG] %N 使用微冲空爆了 Hunter!", attacker);
                    }
                }

                // 重置 Hunter 的跳跃状态
                bIsPouncing[victim] = false;
            }
        }
    }

    return Plugin_Continue;
}

/*
// 游戏自带的infected_hurt事件,也可以用来统计小僵尸命中
public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (IsValidHumanSurvivor(attacker))
    {
        int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");

        // 如果是霰弹枪，确保每次射击只统计一次命中
        if (IsShotgun(weapon))
        {
            if (GetGameTime() - g_fLastShotgunShotTime[attacker] <= 0.1 && 
                !g_bShotgunHitRegistered[attacker])
            {
                g_iEffectiveHits[attacker]++;
                g_bShotgunHitRegistered[attacker] = true;
            }
        }
        else // 其他武器正常统计
        {
            g_iEffectiveHits[attacker]++;
        }
    }
    return Plugin_Continue;
}
*/

// 过滤后的witch,xss实体命中处理
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    // 1. 基础检查
    if (!g_bIsRoundLive) return Plugin_Continue;
        
    if (!IsValidHumanSurvivor(attacker)) return Plugin_Continue;
        
    // 2. 只统计枪械攻击
    if (!IsFirearm(weapon)) return Plugin_Continue;
        
    // 3. 根据武器类型统计命中
    WeaponCategory category = GetWeaponCategory(weapon);
    if (category == WC_SHOTGUN)
    {
        // 霰弹枪特殊处理：每次射击仅统计一次命中
        if (!g_bCurrentShotHitRegistered[attacker])
        {
            g_iEffectiveHits[attacker]++;
            g_bCurrentShotHitRegistered[attacker] = true;
        }
    }
    else if (category != WC_INVALID)
    {
        // 确保每颗子弹只统计一次命中
        if (!g_bShotHitRegistered[attacker])
        {
            g_iEffectiveHits[attacker]++;
            g_bShotHitRegistered[attacker] = true;
        }
    }
    
    return Plugin_Continue;
}

// 特感玩家生成或复活时，重置其击杀标记
public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // 确保是特感玩家
    if (IsValidInfected(client))
    {
        //重置特感的击杀标记
        g_bCurrentShotHitRegistered[client] = false;

        //特感类别
        ZombieClass zClass = view_as<ZombieClass>(GetEntProp(client, Prop_Send, "m_zombieClass"));

        // 根据特感类别挂钩不同的事件
        switch (zClass)
        {
            case ZC_Smoker, ZC_Hunter, ZC_Boomer, ZC_Jockey, ZC_Spitter, ZC_Charger:
            {
                SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_SI);     // 用来统计伤害和命中
                SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);        // 用来统计爆头
            }
            case ZC_Tank:
            {
                SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_Tank);   // 用来统计克的,这个统计人工tank
            }
        }
    }
}

// 计算6只特感的命中次数（g_iHits）、对特感造成的伤害(g_iDamageSI)
public Action OnTakeDamage_SI(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!g_bIsRoundLive) return Plugin_Continue;    // 回合未开始则返回

    if (IsValidHumanSurvivor(attacker))
    {
        // 1. 计算实际伤害(包含近战和枪械)
        if (IsFirearm(weapon) || IsMelee(weapon))
        {
            // 获取特感当前血量
            float health = float(GetEntProp(victim, Prop_Data, "m_iHealth"));
            
            // 计算实际伤害,避免溢出
            float actualDamage = damage;
            if (actualDamage > health)
            {
                actualDamage = health;
            }
            
            // 累加伤害统计
            g_iDamageSI[attacker] += RoundToFloor(actualDamage);
        }

        // 2. 枪械武器的命中统计 
        if (IsFirearm(weapon))
        {
            // 获取武器类型
            WeaponCategory category = GetWeaponCategory(weapon);
            
            if (category == WC_SHOTGUN)
            {
                // 霰弹枪每次射击只统计一次命中
                if (!g_bCurrentShotHitRegistered[attacker])
                {
                    g_iHits[attacker]++;
                    g_bCurrentShotHitRegistered[attacker] = true;
                }
            }
            else if (category != WC_INVALID)
            {
                // 确保每颗子弹只统计一次命中
                if (!g_bShotHitRegistered[attacker])
                {
                    g_iHits[attacker]++;
                    g_bShotHitRegistered[attacker] = true;
                }
            }
        }
    }

    return Plugin_Continue;
}

// 特感爆头次数（g_iHeadshots）统计现在改为独立的事件
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    // 1. 基础检查
    if (!IsValidHumanSurvivor(attacker)) return Plugin_Continue;
        
    // 2. 获取并验证武器
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (!IsFirearm(weapon)) return Plugin_Continue;
        
    // 3. 只处理爆头
    if (hitgroup != HITGROUP_HEAD) return Plugin_Continue;

    WeaponCategory category = GetWeaponCategory(weapon);
        
    // 4. 根据武器类型统计爆头
    if (category == WC_SHOTGUN)
    {
        // 霰弹枪特殊处理：每次射击仅统计一次爆头
        if (!g_bShotgunHeadshotRegistered[attacker])
        {
            g_iHeadshots[attacker]++;
            g_bShotgunHeadshotRegistered[attacker] = true;
        }
    }
    else if (category != WC_INVALID)
    {
        // 确保每颗子弹只统计一次命中
        if (!g_bShotHitRegistered[attacker])
        {
            g_iHeadshots[attacker]++;
            g_bShotHitRegistered[attacker] = true;
        }
    }
    
    return Plugin_Continue;
}

// 对克攻击次数
public Action OnTakeDamage_Tank(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    // 1. 基础检查
    if (!g_bIsRoundLive) return Plugin_Continue;
        
    if (!IsValidHumanSurvivor(attacker)) return Plugin_Continue;
        
    // 2. 只统计枪械攻击
    if (!IsFirearm(weapon)) return Plugin_Continue;
        
    // 3. 根据武器类型分别处理
    WeaponCategory category = GetWeaponCategory(weapon);
    if (category == WC_SHOTGUN)
    {
        // 霰弹枪特殊处理：每次射击仅统计一次命中
        if (!g_bCurrentShotHitRegistered[attacker])
        {
            g_iTankHits[attacker]++;
            g_bCurrentShotHitRegistered[attacker] = true;
        }
    }
    else if (category != WC_INVALID)
    {
        // 确保每颗子弹只统计一次命中
        if (!g_bShotHitRegistered[attacker])
        {
            g_iTankHits[attacker]++;
            g_bShotHitRegistered[attacker] = true;
        }
    }
    
    return Plugin_Continue;
}

// 对克丢出来的饼的攻击次数
public Action OnTakeDamage_TankRock(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    // 1. 基础检查
    if (!g_bIsRoundLive) return Plugin_Continue;
        
    if (!IsValidHumanSurvivor(attacker)) return Plugin_Continue;
        
    // 2. 只统计枪械攻击
    if (!IsFirearm(weapon)) return Plugin_Continue;
        
    // 3. 根据武器类型分别处理
    WeaponCategory category = GetWeaponCategory(weapon);
    if (category == WC_SHOTGUN)
    {
        // 霰弹枪特殊处理：每次射击仅统计一次命中
        if (!g_bCurrentShotHitRegistered[attacker])
        {
            g_iTankRockHits[attacker]++;
            g_bCurrentShotHitRegistered[attacker] = true;
        }
    }
    else if (category != WC_INVALID)
    {
        // 确保每颗子弹只统计一次命中
        if (!g_bShotHitRegistered[attacker])
        {
            g_iTankRockHits[attacker]++;
            g_bShotHitRegistered[attacker] = true;
        }
    }
    
    return Plugin_Continue;
}

// 武器射击事件处理
public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bIsRoundLive) return Plugin_Continue;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidHumanSurvivor(client)) return Plugin_Continue;
    
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1) return Plugin_Continue;

    switch(GetWeaponCategory(weapon))
    {
        case WC_SHOTGUN:
        {
            g_iShots[client]++;
            g_bCurrentShotHitRegistered[client] = false;
            g_bShotgunHitRegistered[client] = false;
            g_bShotgunHeadshotRegistered[client] = false;
        }
        case WC_FULLAUTO, WC_SEMIAUTO:
        {
            g_iShots[client]++;
            g_bShotHitRegistered[client] = false;
        }
    }
    return Plugin_Continue;
}

// 回合结束处理
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // 如果已经记录过本轮统计，则跳过
    if (g_bHasLoggedStats) 
    {
        return Plugin_Continue;
    }
    
    // 设置已记录标记
    g_bHasLoggedStats = true;

    char sDate[12], sTime[12];
    FormatTime(sDate, sizeof(sDate), "%Y-%m-%d");
    FormatTime(sTime, sizeof(sTime), "%H:%M:%S");
    
    char sLogPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sLogPath, sizeof(sLogPath), "logs/player/%s.log", sDate);
    
    // 日志头信息
    LogToFileEx(sLogPath, "══════════════════════════════");
    LogToFileEx(sLogPath, "回合结束时间：%s", sTime);
    
    char mapName[64];
    if (GetCurrentMap(mapName, sizeof(mapName)))
    {
        LogToFileEx(sLogPath, "当前地图：%s", mapName); 
    }
    LogToFileEx(sLogPath, "══════════════════════════════");
    
    // 玩家数据遍历
    int dataCount;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanSurvivor(client)) continue;
        bool hasData = 
        // 只要玩家有任何一条统计数据，就继续记录
            g_iShots[client] > 0 || 
            g_iHits[client] > 0 || 
            g_iEffectiveHits[client] > 0 || 
            g_iHeadshots[client] > 0 || 
            g_iTankHits[client] > 0 || 
            g_iTankRockHits[client] > 0 || 
            g_iDamageSI[client] > 0 || 
            g_iKilledSI[client] > 0;

        if (!hasData) continue;

        char sName[MAX_NAME_LENGTH];
        GetClientName(client, sName, sizeof(sName));
        TrimUTF8String(sName, 24); // 限制名称长度
        
        // 计算空枪次数：空枪 =     总开枪次数       -   对小僵尸和witch次数    -     对特感次数        -    对克次数      -      对克的饼次数
        g_iMissedShots[client] = g_iShots[client] - g_iEffectiveHits[client] - g_iHits[client] - g_iTankHits[client] - g_iTankRockHits[client];
        
        // 确保空枪数不会为负数
        if (g_iMissedShots[client] < 0)
        {
            g_iMissedShots[client] = 0;
        }
        
        // 其他命中：对小僵尸和witch开枪次数=  总开枪次数  -       空枪次数     -   对特感次数  -       对克次数         -        对克的饼次数
        //witch和xss事件合并后不需要计算了
        //g_iEffectiveHits[client] = g_iShots[client] - g_iMissedShots[client] - g_iHits[client] - g_iTankHits[client] - g_iTankRockHits[client];
        
        // 计算比率
        // 其他命中率
        float hitRate = CalculateRate(g_iEffectiveHits[client], (g_iMissedShots[client] + g_iEffectiveHits[client]));
        // 特感爆头率
        float hsRate = CalculateRate(g_iHeadshots[client], (g_iMissedShots[client] + g_iHits[client]));
        // 特感命中率
        float siHitRate = CalculateRate(g_iHits[client], (g_iMissedShots[client] + g_iHits[client]));
        
        // 格式化输出
        LogToFileEx(sLogPath, "────────回合命中统计───────");
        LogToFileEx(sLogPath, "　玩家ID: %s", sName);
        LogToFileEx(sLogPath, "　射击数：%10d", g_iShots[client]);
        LogToFileEx(sLogPath, "　空枪数：%10d", g_iMissedShots[client]);
        LogToFileEx(sLogPath, "　特感命中数：%10d", g_iHits[client]); 
        LogToFileEx(sLogPath, "　特感爆头数：%10d", g_iHeadshots[client]);
        LogToFileEx(sLogPath, "　其他命中数：%10d", g_iEffectiveHits[client]);
        LogToFileEx(sLogPath, "　其他命中率：%9.2f%%", hitRate);
        LogToFileEx(sLogPath, "　特感命中率：%9.2f%%", siHitRate);
        LogToFileEx(sLogPath, "　特感爆头率：%9.2f%%", hsRate);
        LogToFileEx(sLogPath, "──────────────────────────");
        LogToFileEx(sLogPath, "　霰弹空爆数：%10d", g_iShotgunMidairHunters[client]);
        LogToFileEx(sLogPath, "　近战空爆数：%10d", g_iMeleeMidairHunters[client]);
        LogToFileEx(sLogPath, "　微冲空爆数：%10d", g_iSMGUnder10Kills[client]);
        LogToFileEx(sLogPath, "　特感击杀量：%10d", g_iKilledSI[client]);
        LogToFileEx(sLogPath, "　对特感造成伤害：%10d", g_iDamageSI[client]);
        LogToFileEx(sLogPath, "　被Hunter扑中: %10d", g_iHunted[client]);
        LogToFileEx(sLogPath, "　被其他特感控制：%10d", g_iControlled[client]);
        LogToFileEx(sLogPath, "　对克攻击次数：%10d", g_iTankHits[client]);
        LogToFileEx(sLogPath, "　点克的饼次数：%10d", g_iTankRockHits[client]);
        LogToFileEx(sLogPath, "──────────────────────────");
        
        // 保存上一回合的统计数据
        g_iLastRoundShots[client] = g_iShots[client];
        g_iLastRoundHits[client] = g_iHits[client];
        g_iLastRoundHeadshots[client] = g_iHeadshots[client];
        g_iLastRoundShotgunMidairHunters[client] = g_iShotgunMidairHunters[client];
        g_iLastRoundMeleeMidairHunters[client] = g_iMeleeMidairHunters[client];
        g_iLastRoundSMGUnder10Kills[client] = g_iSMGUnder10Kills[client];
        g_iLastRoundHunted[client] = g_iHunted[client];
        g_iLastRoundKilledSI[client] = g_iKilledSI[client];
        g_iLastRoundDamageSI[client] = g_iDamageSI[client];
        g_iLastRoundControlled[client] = g_iControlled[client];
        g_iLastRoundMissedShots[client] = g_iMissedShots[client];
        g_iLastRoundEffectiveHits[client] = g_iEffectiveHits[client];
        g_iLastRoundTankHits[client] = g_iTankHits[client];
        g_iLastRoundTankRockHits[client] = g_iTankRockHits[client];

        // 保存统计数据到 .../data/tongji.txt 里
        SavePlayerStats(client);

        dataCount++;
    }
    
    // 无数据提示
    if (dataCount == 0)
    {
        LogToFileEx(sLogPath, "（本回合无有效战斗数据）");
    }
    
    LogToFileEx(sLogPath, "══════════════════════════════\n");

    // 先自动打印回合统计
    if (g_cvAutoPrintStats.BoolValue)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            // 只处理未打印过的生还玩家
            if (IsClientInGame(client) && 
                GetClientTeam(client) == 2 && 
                !g_bHasPrintedStats[client] && 
                !IsFakeClient(client))
            {
                Command_Tongji(client, 0);
                g_bHasPrintedStats[client] = true; // 再立即标记为已打印
            }
        }
    }

    /* 丢到OnRoundIsLive里面就行
    // 再给所有生还玩家重置统计数据
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ResetClientStats(client);   //回合结束，打印结束后，数据统计重置一遍
        }
    }
    */

    // 当回合结束时，自动标记为插件未激活状态，放在这里避免影响结算统计
    g_bIsRoundLive = false;

    return Plugin_Continue;
}

// 保存玩家统计数据到 tongji.txt
void SavePlayerStats(int client)
{
    char sSteamID[32];
    if (!GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
    {
        return;
    }

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/tongji.txt");

    // 读取现有数据
    KeyValues kv = new KeyValues("PlayerStats");
    if (kv.ImportFromFile(sPath))
    {
        if (kv.JumpToKey(sSteamID, true))
        {
            // 更新统计数据
            kv.SetNum("Shots", kv.GetNum("Shots", 0) + g_iShots[client]);
            kv.SetNum("Hits", kv.GetNum("Hits", 0) + g_iHits[client]);
            kv.SetNum("Headshots", kv.GetNum("Headshots", 0) + g_iHeadshots[client]);
            kv.SetNum("ShotgunMidairHunters", kv.GetNum("ShotgunMidairHunters", 0) + g_iShotgunMidairHunters[client]);
            kv.SetNum("MeleeMidairHunters", kv.GetNum("MeleeMidairHunters", 0) + g_iMeleeMidairHunters[client]);
            kv.SetNum("SMGUnder10Kills", kv.GetNum("SMGUnder10Kills", 0) + g_iSMGUnder10Kills[client]);
            kv.SetNum("Hunted", kv.GetNum("Hunted", 0) + g_iHunted[client]);
            kv.SetNum("KilledSI", kv.GetNum("KilledSI", 0) + g_iKilledSI[client]);
            kv.SetNum("DamageSI", kv.GetNum("DamageSI", 0) + g_iDamageSI[client]);
            kv.SetNum("Controlled", kv.GetNum("Controlled", 0) + g_iControlled[client]);
            kv.SetNum("MissedShots", kv.GetNum("MissedShots", 0) + g_iMissedShots[client]);
            kv.SetNum("EffectiveHits", kv.GetNum("EffectiveHits", 0) + g_iEffectiveHits[client]);
            kv.SetNum("TankHits", kv.GetNum("TankHits", 0) + g_iTankHits[client]);
            kv.SetNum("TankRockHits", kv.GetNum("TankRockHits", 0) + g_iTankRockHits[client]);
        }
    }
    else
    {
        // 如果文件不存在，创建新的 KeyValues 结构
        kv.JumpToKey(sSteamID, true);
        kv.SetNum("Shots", g_iShots[client]);
        kv.SetNum("Hits", g_iHits[client]);
        kv.SetNum("Headshots", g_iHeadshots[client]);
        kv.SetNum("ShotgunMidairHunters", g_iShotgunMidairHunters[client]);
        kv.SetNum("MeleeMidairHunters", g_iMeleeMidairHunters[client]);
        kv.SetNum("SMGUnder10Kills", g_iSMGUnder10Kills[client]);
        kv.SetNum("Hunted", g_iHunted[client]);
        kv.SetNum("KilledSI", g_iKilledSI[client]);
        kv.SetNum("DamageSI", g_iDamageSI[client]);
        kv.SetNum("Controlled", g_iControlled[client]);
        kv.SetNum("MissedShots", g_iMissedShots[client]);
        kv.SetNum("EffectiveHits", g_iEffectiveHits[client]);
        kv.SetNum("TankHits", g_iTankHits[client]);
        kv.SetNum("TankRockHits", g_iTankRockHits[client]);
    }

    // 保存数据到文件
    kv.Rewind();
    kv.ExportToFile(sPath);
    delete kv;
}

// 命令处理函数:/tongji
public Action Command_Tongji(int client, int args)
{
    // 检查是否允许打印
    //float currentTime = GetGameTime();
    //if (currentTime - g_fLastTongjiPrintTime[client] < 10.0)
    //{
    //    ReplyToCommand(client, "\x04[提示] 每 10 秒只能打印一次统计数据，请稍后再试。");
    //    return Plugin_Handled;
    //}

    // 更新上次打印时间
    //g_fLastTongjiPrintTime[client] = currentTime;

    // 检查是否有上一回合的统计数据
    if (g_iLastRoundShots[client] == 0 && g_iLastRoundHits[client] == 0)
    {
        ReplyToCommand(client, "\x04没有找到上一回合的统计数据, 请等本轮结束后再试。");
        return Plugin_Handled;
    }

    // 计算空枪次数
    int missedShots = g_iLastRoundShots[client] - g_iLastRoundEffectiveHits[client] - g_iLastRoundHits[client] - g_iLastRoundTankHits[client] - g_iLastRoundTankRockHits[client];
    
    // 计算其他命中数
    //合并后不需要了
    //int effectiveHits = g_iLastRoundShots[client] - missedShots - g_iLastRoundHits[client] - g_iLastRoundTankHits[client] - g_iLastRoundTankRockHits[client];
    
    // 计算比率
    //其他命中率
    float hitRate = CalculateRate(g_iLastRoundEffectiveHits[client], (missedShots + g_iLastRoundEffectiveHits[client]));
    //特感爆头率
    float hsRate = CalculateRate(g_iLastRoundHeadshots[client], (missedShots + g_iLastRoundHits[client]));
    //特感命中率
    float siHitRate = CalculateRate(g_iLastRoundHits[client], (missedShots + g_iLastRoundHits[client]));

    // 在聊天框中打印统计数据
    PrintToChat(client, "\x01───────────────────────────");
    PrintToChat(client, "\x04[星云猫猫统计]");
    PrintToChat(client, "\x01───────────────────────────");
    PrintToChat(client, "\x03玩家ID：\x04%N", client);
    PrintToChat(client, "\x03射击数：\x04%10d", g_iLastRoundShots[client]);
    PrintToChat(client, "\x03空枪数：\x04%10d", missedShots);
    PrintToChat(client, "\x03特感命中数：\x04%10d", g_iLastRoundHits[client]);
    PrintToChat(client, "\x03特感爆头数：\x04%10d", g_iLastRoundHeadshots[client]);
    PrintToChat(client, "\x03其他命中数：\x04%10d", g_iLastRoundEffectiveHits[client]);
    PrintToChat(client, "\x03其他命中率：\x04%9.2f%%", hitRate);
    PrintToChat(client, "\x03特感命中率：\x04%9.2f%%", siHitRate);
    PrintToChat(client, "\x03特感爆头率：\x04%9.2f%%", hsRate);
    PrintToChat(client, "\x01──────────────────────────");
    PrintToChat(client, "\x03霰弹空爆数：\x04%10d", g_iLastRoundShotgunMidairHunters[client]);
    PrintToChat(client, "\x03近战空爆数：\x04%10d", g_iLastRoundMeleeMidairHunters[client]);
    PrintToChat(client, "\x03微冲空爆数：\x04%10d", g_iLastRoundSMGUnder10Kills[client]);
    PrintToChat(client, "\x03特感击杀量：\x04%10d", g_iLastRoundKilledSI[client]);
    PrintToChat(client, "\x03对特感造成伤害：\x04%10d", g_iLastRoundDamageSI[client]);
    PrintToChat(client, "\x03被Hunter扑中：\x04%10d", g_iLastRoundHunted[client]);
    PrintToChat(client, "\x03被其他特感控制：\x04%10d", g_iLastRoundControlled[client]);
    PrintToChat(client, "\x03对克攻击次数：\x04%10d", g_iLastRoundTankHits[client]);
    PrintToChat(client, "\x03点克的饼次数：\x04%10d", g_iLastRoundTankRockHits[client]);
    PrintToChat(client, "\x01──────────────────────────");

    return Plugin_Handled;
}

// 命令处理函数:/quanbutongji
public Action Command_QuanbuTongji(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "此命令只能在游戏内使用.");
        return Plugin_Handled;
    }

    char sSteamID[32];
    if (!GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID)))
    {
        ReplyToCommand(client, "\x04无法获取您的SteamID, 请稍后重试.");
        return Plugin_Handled;
    }

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/tongji.txt");

    KeyValues kv = new KeyValues("PlayerStats");
    if (!kv.ImportFromFile(sPath))
    {
        ReplyToCommand(client, "\x04未找到统计数据文件。");
        delete kv;
        return Plugin_Handled;
    }

    if (!kv.JumpToKey(sSteamID, false))
    {
        ReplyToCommand(client, "\x04未找到您的统计数据，在服务器里打两场吧~");
        delete kv;
        return Plugin_Handled;
    }

    // 读取统计数据
    int shots = kv.GetNum("Shots", 0);
    int hits = kv.GetNum("Hits", 0);
    int headshots = kv.GetNum("Headshots", 0);
    int shotgunMidairHunters = kv.GetNum("ShotgunMidairHunters", 0);
    int meleeMidairHunters = kv.GetNum("MeleeMidairHunters", 0);
    int smgUnder10Kills = kv.GetNum("SMGUnder10Kills", 0);
    int hunted = kv.GetNum("Hunted", 0);
    int killedSI = kv.GetNum("KilledSI", 0);
    int damageSI = kv.GetNum("DamageSI", 0);
    int controlled = kv.GetNum("Controlled", 0);
    int missedShots = kv.GetNum("MissedShots", 0);
    int effectiveHits = kv.GetNum("EffectiveHits", 0);
    int tankHits = kv.GetNum("TankHits", 0);
    int tankRockHits = kv.GetNum("TankRockHits", 0);

    // 计算比率
    // 其他命中率
    float hitRate = CalculateRate(effectiveHits, (missedShots + effectiveHits));
    // 特感爆头率
    float hsRate = CalculateRate(headshots, (missedShots + hits));
    // 特感命中率
    float siHitRate = CalculateRate(hits, (missedShots + hits));

    // 在聊天框中打印统计数据
    PrintToChat(client, "\x01───────────────────────────");
    PrintToChat(client, "\x04[星云猫猫统计]");
    PrintToChat(client, "\x01─────────历史数据──────────");
    PrintToChat(client, "\x03玩家ID：\x04%N", client);
    PrintToChat(client, "\x03射击数：\x04%10d", shots);
    PrintToChat(client, "\x03爆头数：\x04%10d", headshots);
    PrintToChat(client, "\x03空枪数：\x04%10d", missedShots);
    PrintToChat(client, "\x03特感命中数：\x04%10d", hits);
    PrintToChat(client, "\x03其他命中数：\x04%10d", effectiveHits);
    PrintToChat(client, "\x03其他命中率：\x04%9.2f%%", hitRate);
    PrintToChat(client, "\x03特感命中率：\x04%9.2f%%", siHitRate);
    PrintToChat(client, "\x03特感爆头率：\x04%9.2f%%", hsRate);
    PrintToChat(client, "\x01──────────────────────────");
    PrintToChat(client, "\x03霰弹空爆数：\x04%10d", shotgunMidairHunters);
    PrintToChat(client, "\x03近战空爆数：\x04%10d", meleeMidairHunters);
    PrintToChat(client, "\x03微冲空爆数：\x04%10d", smgUnder10Kills);
    PrintToChat(client, "\x03特感击杀量：\x04%10d", killedSI);
    PrintToChat(client, "\x03对特感造成伤害：\x04%10d", damageSI);
    PrintToChat(client, "\x03被Hunter扑中：\x04%10d", hunted);
    PrintToChat(client, "\x03被其他特感控制：\x04%10d", controlled);
    PrintToChat(client, "\x03对克攻击次数：\x04%10d", tankHits);
    PrintToChat(client, "\x03点克饼的次数：\x04%10d", tankRockHits);
    PrintToChat(client, "\x01──────────────────────────");

    delete kv;
    return Plugin_Handled;
}

// 中文安全截断函数,防止奇形怪状的id
void TrimUTF8String(char[] str, int maxBytes)
{
    int len = strlen(str);
    int currentBytes, lastSafePos;
    
    for(int i=0; i<len; i++)
    {
        int thisByte = str[i];
        if(thisByte & 0x80) // 中文检测
        {
            if(i+2 >= len) break;
            currentBytes += 3; // UTF-8中文字符按3字节计算
            i += 2;
        }
        else
        {
            currentBytes++;
        }
        
        if(currentBytes <= maxBytes)
        {
            lastSafePos = i+1;
        }
        else
        {
            break;
        }
    }
    
    if(lastSafePos < len)
    {
        str[lastSafePos] = '\0';
        if(lastSafePos >=3 && str[lastSafePos-3] & 0x80)
        {
            str[lastSafePos-3] = '\0'; // 防止截断半个中文
        }
        StrCat(str, maxBytes, "…");
    }
}

// 计算百分比
float CalculateRate(int numerator, int denominator)
{
    if (denominator <= 0) return 0.0;
    return (float(numerator) / float(denominator)) * 100.0;
}

// 武器分类检测
WeaponCategory GetWeaponCategory(int weapon)
{
    char cls[32];
    GetEntityClassname(weapon, cls, sizeof(cls));
    
    if (StrContains(cls, "shotgun_chrome") != -1) return WC_SHOTGUN;
    if (StrContains(cls, "pumpshotgun") != -1) return WC_SHOTGUN;
    if (StrContains(cls, "shotgun_spas") != -1) return WC_SHOTGUN;
    if (StrContains(cls, "autoshotgun") != -1) return WC_SHOTGUN;
    if (StrContains(cls, "smg") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "smg_silenced") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "smg_mp5") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "rifle") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "rifle_desert") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "rifle_ak47") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "rifle_sg552") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "rifle_m60") != -1) return WC_FULLAUTO;
    if (StrContains(cls, "pistol") != -1) return WC_SEMIAUTO;
    if (StrContains(cls, "pistol_magnum") != -1) return WC_SEMIAUTO;
    if (StrContains(cls, "sniper_military") != -1) return WC_SEMIAUTO;
    if (StrContains(cls, "sniper_scout") != -1) return WC_SEMIAUTO;
    if (StrContains(cls, "sniper_awp") != -1) return WC_SEMIAUTO;
    if (StrContains(cls, "hunting_rifle") != -1) return WC_SEMIAUTO;
    return WC_INVALID;
}

// 验证有效幸存者，排除机器人
bool IsValidHumanSurvivor(int client)
{
    return (client > 0 && 
            client <= MaxClients && 
            IsClientInGame(client) && 
            GetClientTeam(client) == 2 && 
            !IsFakeClient(client));
}

// 验证有效特感，需要包含ai特感
bool IsValidInfected(int client)
{
    return (client > 0 && 
            client <= MaxClients && 
            IsClientInGame(client) && 
            GetClientTeam(client) == 3);
}

/*
// 霰弹枪辅助函数（witch、xss那里用的）
bool IsShotgun(int weapon)
{
    if (weapon == -1) return false;

    char weaponClass[64];
    GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));

    return StrContains(weaponClass, "shotgun") != -1;
}
*/

//判断是否是枪械武器，排除麻辣烫等火焰攻击次数
bool IsFirearm(int weapon)
{
    if (weapon == -1) return false;

    char weaponClass[64];
    GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));

    // 判断是否为枪械类武器
    return (StrContains(weaponClass, "pistol") != -1 ||
            StrContains(weaponClass, "pistol_magnum") != -1 ||
            StrContains(weaponClass, "rifle_m60") != -1 ||
            StrContains(weaponClass, "smg") != -1 ||
            StrContains(weaponClass, "smg_silenced") != -1 ||
            StrContains(weaponClass, "smg_mp5") != -1 ||
            StrContains(weaponClass, "rifle") != -1 ||
            StrContains(weaponClass, "rifle_desert") != -1 ||
            StrContains(weaponClass, "rifle_ak47") != -1 ||
            StrContains(weaponClass, "rifle_sg552") != -1 ||
            StrContains(weaponClass, "pumpshotgun") != -1 ||
            StrContains(weaponClass, "shotgun_chrome") != -1 ||
            StrContains(weaponClass, "shotgun_spas") != -1 ||
            StrContains(weaponClass, "autoshotgun") != -1 ||
            StrContains(weaponClass, "sniper_military") != -1 ||
            StrContains(weaponClass, "sniper_scout") != -1 ||
            StrContains(weaponClass, "sniper_awp") != -1 ||
            StrContains(weaponClass, "hunting_rifle") != -1);
}

// 判断是否为近战
bool IsMelee(int weapon)
{
    if (weapon == -1) return false;

    char weaponClass[64];
    GetEdictClassname(weapon, weaponClass, sizeof(weaponClass));

    return (StrContains(weaponClass, "melee") != -1);
}