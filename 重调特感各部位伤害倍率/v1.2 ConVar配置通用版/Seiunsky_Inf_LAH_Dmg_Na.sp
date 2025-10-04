
/*
* 更新日志：
    v1.0 ：为啥要考虑boomer,这货不是50hp吗?算鸟.
    v1.1 : 限制最大伤害量不能超过特感本身血量,避免出现其他插件的兼容问题.
    v1.2b : 修复点小问题.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

ConVar 
    g_cvPluginEnabled,
    g_cvDebugEnabled,
    g_cvSmokerHead,
    g_cvSmokerBody,
    g_cvSmokerArm,
    g_cvSmokerLeg,
    g_cvHunterHead,
    g_cvHunterBody,
    g_cvHunterArm,
    g_cvHunterLeg,
    g_cvJockeyHead,
    g_cvJockeyBody,
    g_cvJockeyArm,
    g_cvJockeyLeg,
    g_cvChargerHead,
    g_cvChargerBody,
    g_cvChargerArm,
    g_cvChargerLeg,
    g_cvBoomerHead,
    g_cvBoomerBody,
    g_cvBoomerArm,
    g_cvBoomerLeg,
    g_cvSpitterHead,
    g_cvSpitterBody,
    g_cvSpitterArm,
    g_cvSpitterLeg,
    g_cvSmokerChest,
    g_cvHunterChest,
    g_cvBoomerChest,
    g_cvAllowedWeapons;

public Plugin myinfo =
{
    name = "重调特感各部位伤害倍率",
    author = "Seiunsky Maomao",
    description = "枪械对特感的不同部位重新设置不同伤害倍率.",
    version = "1.2b",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    g_cvPluginEnabled = CreateConVar("sm_inf_lah_dmg_enabled", "1", "插件开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAllowedWeapons = CreateConVar("sm_inf_lah_dmg_wp", "weapon_sniper_scout,weapon_sniper_awp", "允许的武器列表,用逗号分隔(不仅仅能填入狙)", FCVAR_NONE);

    g_cvDebugEnabled = CreateConVar("sm_inf_lah_dmg_debug", "0", "调试开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvSmokerHead = CreateConVar("sm_inf_lah_dmg_smoker_head", "4.00", "Smoker头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvSmokerChest = CreateConVar("sm_inf_lah_dmg_smoker_chest", "1.00", "Smoker胸部伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvSmokerBody = CreateConVar("sm_inf_lah_dmg_smoker_body", "1.25", "Smoker胃部伤害倍率. | 原版:1.25", FCVAR_NONE, true, 0.0);
    g_cvSmokerArm = CreateConVar("sm_inf_lah_dmg_smoker_arm", "1.00", "Smoker手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvSmokerLeg = CreateConVar("sm_inf_lah_dmg_smoker_leg", "0.75", "Smoker腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    g_cvHunterHead = CreateConVar("sm_inf_lah_dmg_hunter_head", "4.00", "Hunter头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvHunterChest = CreateConVar("sm_inf_lah_dmg_hunter_chest", "1.00", "Hunter胸部伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvHunterBody = CreateConVar("sm_inf_lah_dmg_hunter_body", "1.25", "Hunter胃部伤害倍率. | 原版:1.25", FCVAR_NONE, true, 0.0);
    g_cvHunterArm = CreateConVar("sm_inf_lah_dmg_hunter_arm", "1.00", "Hunter手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvHunterLeg = CreateConVar("sm_inf_lah_dmg_hunter_leg", "0.75", "Hunter腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    g_cvJockeyHead = CreateConVar("sm_inf_lah_dmg_jockey_head", "4.00", "Jockey头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvJockeyBody = CreateConVar("sm_inf_lah_dmg_jockey_body", "1.00", "Jockey身体伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvJockeyArm = CreateConVar("sm_inf_lah_dmg_jockey_arm", "1.00", "Jockey手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvJockeyLeg = CreateConVar("sm_inf_lah_dmg_jockey_leg", "0.75", "Jockey腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    g_cvChargerHead = CreateConVar("sm_inf_lah_dmg_charger_head", "4.00", "Charger头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvChargerBody = CreateConVar("sm_inf_lah_dmg_charger_body", "1.00", "Charger身体伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvChargerArm = CreateConVar("sm_inf_lah_dmg_charger_arm", "1.00", "Charger手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvChargerLeg = CreateConVar("sm_inf_lah_dmg_charger_leg", "0.75", "Charger腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    g_cvBoomerHead = CreateConVar("sm_inf_lah_dmg_boomer_head", "4.00", "Boomer头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvBoomerChest = CreateConVar("sm_inf_lah_dmg_boomer_chest", "1.00", "Boomer胸部伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvBoomerBody = CreateConVar("sm_inf_lah_dmg_boomer_body", "1.25", "Boomer胃部伤害倍率. | 原版:1.25", FCVAR_NONE, true, 0.0);
    g_cvBoomerArm = CreateConVar("sm_inf_lah_dmg_boomer_arm", "1.00", "Boomer手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvBoomerLeg = CreateConVar("sm_inf_lah_dmg_boomer_leg", "0.75", "Boomer腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    g_cvSpitterHead = CreateConVar("sm_inf_lah_dmg_spitter_head", "4.00", "Spitter头部伤害倍率. | 原版:4.00", FCVAR_NONE, true, 0.0);
    g_cvSpitterBody = CreateConVar("sm_inf_lah_dmg_spitter_body", "1.00", "Spitter身体伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvSpitterArm = CreateConVar("sm_inf_lah_dmg_spitter_arm", "1.00", "Spitter手臂伤害倍率. | 原版:1.00", FCVAR_NONE, true, 0.0);
    g_cvSpitterLeg = CreateConVar("sm_inf_lah_dmg_spitter_leg", "0.75", "Spitter腿部伤害倍率. | 原版:0.75", FCVAR_NONE, true, 0.0);

    HookEvent("player_spawn", Event_PlayerSpawn);

    AutoExecConfig(true, "Seiunsky_Inf_LAH_Dmg_Na");
}

//特感生成监听
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (IsValidClient(client) && IsInfected(client))
    {
        // sdkhook应该是会在特感死亡时自动取消，随后对新生成的特感重新挂钩
        SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

//伤害处理
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    if (!g_cvPluginEnabled.BoolValue)   //插件是否开启
        return Plugin_Continue;

    //确保攻击者是有效的生还,受害者是有效的特感
    if (!IsSurvivor(attacker) || !IsInfected(victim))
        return Plugin_Continue;

    //获取攻击者当前使用的武器实体
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)   //特殊情况也直接返回
        return Plugin_Continue;

    char weaponName[32];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName)); //武器类名获取

    //调试,武器类名
    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 当前武器: %s", weaponName);
    }

    // 检查武器是否在允许的列表中
    if (!IsSniperWeapon(weaponName))
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 武器 %s 不在允许列表中,跳过计算", weaponName);
        }
        return Plugin_Continue;
    }

    float baseDamage = damage;

    /*
    // ---------------------------
    //  Hit Group standards
    // ---------------------------
    //#define HITGROUP_GENERIC     0
    //#define HITGROUP_HEAD        1
    //#define HITGROUP_CHEST       2
    //#define HITGROUP_STOMACH     3
    //#define HITGROUP_LEFTARM     4    
    //#define HITGROUP_RIGHTARM    5
    //#define HITGROUP_LEFTLEG     6
    //#define HITGROUP_RIGHTLEG    7
    //#define HITGROUP_GEAR        10            // alerts NPC, but doesn't do damage or bleed (1/100th damage)
    */

    //移除游戏默认的部位伤害倍率
    switch (hitgroup)
    {
        case 0:
            baseDamage = damage;        //默认1.00
        case 1:
            baseDamage = damage / 4.00; //移除游戏默认的4倍爆头加成
        case 2:
            baseDamage = damage;        //默认1.00
        case 3:
            baseDamage = damage / 1.25; //移除游戏默认的1.25倍身体伤害
        case 4, 5:
            baseDamage = damage;        //默认1.00
        case 6, 7:
            baseDamage = damage / 0.75; //移除游戏默认的0.75倍腿部伤害
        default:
            baseDamage = damage;        //不做处理
    }

    // 获取特感类型
    char classname[32];
    if (IsInfected(victim))
    {
        // 获取特感的具体类型（返回值是整数）
        int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
        
        // 将整数转换为对应的特感名称
        switch (zombieClass)
        {
            case 1: strcopy(classname, sizeof(classname), "smoker");
            case 2: strcopy(classname, sizeof(classname), "boomer");
            case 3: strcopy(classname, sizeof(classname), "hunter");
            case 4: strcopy(classname, sizeof(classname), "spitter");
            case 5: strcopy(classname, sizeof(classname), "jockey");
            case 6: strcopy(classname, sizeof(classname), "charger");
        }
        /*
        //调试
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 枚举id: %d, 特感: %s", zombieClass, classname);
        }
        */
    }
    else
    {
        //不是对应特感则直接返回
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 不是特感,跳过处理.");
        }
        return Plugin_Continue;
    }

    //获取伤害倍率
    float multiplier = GetDamageMultiplier(classname, hitgroup);

    //应用伤害倍率
    damage = baseDamage * multiplier;

    return Plugin_Changed;
}

//对应特感和伤害倍率
float GetDamageMultiplier(const char[] classname, int hitgroup)
{
    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 特感: %s, 部位: %d", classname, hitgroup);
    }

    if (StrEqual(classname, "smoker"))
    {
        switch (hitgroup)
        {
            case 1: return g_cvSmokerHead.FloatValue;   //头部
            case 2: return g_cvSmokerChest.FloatValue;   //胸腔
            case 3: return g_cvSmokerBody.FloatValue;   //身体
            case 4: return g_cvSmokerArm.FloatValue;    //左手
            case 5: return g_cvSmokerArm.FloatValue;    //右手
            case 6: return g_cvSmokerLeg.FloatValue;    //左腿
            case 7: return g_cvSmokerLeg.FloatValue;    //右腿
            default: return 1.0;
        }
    }
    else if (StrEqual(classname, "hunter"))
    {
        switch (hitgroup)
        {
            case 1: return g_cvHunterHead.FloatValue;
            case 2: return g_cvHunterChest.FloatValue;
            case 3: return g_cvHunterBody.FloatValue;
            case 4: return g_cvHunterArm.FloatValue;
            case 5: return g_cvHunterArm.FloatValue;
            case 6: return g_cvHunterLeg.FloatValue;
            case 7: return g_cvHunterLeg.FloatValue;
            default: return 1.0;
        }
    }
    else if (StrEqual(classname, "jockey"))
    {
        switch (hitgroup)
        {
            case 0: return g_cvJockeyBody.FloatValue;   //猴子0是身体
            case 1: return g_cvJockeyHead.FloatValue;   //1是头
            case 2: return g_cvJockeyArm.FloatValue;    //猴子2是手臂
            case 3: return g_cvJockeyArm.FloatValue;    //3是手臂
            case 4: return g_cvJockeyLeg.FloatValue;    //4是腿
            case 5: return g_cvJockeyLeg.FloatValue;    //5是腿
            default: return 1.0;
        }
    }
    else if (StrEqual(classname, "charger"))
    {
        switch (hitgroup)
        {
            case 0: return g_cvChargerBody.FloatValue;   //牛0是身体
            case 1: return g_cvChargerHead.FloatValue;   //1是头
            case 2: return g_cvChargerArm.FloatValue;    //牛2是手臂
            case 3: return g_cvChargerArm.FloatValue;    //3是手臂
            case 4: return g_cvChargerLeg.FloatValue;    //4是腿
            case 5: return g_cvChargerLeg.FloatValue;    //5是腿
            default: return 1.0;
        }
    }
    else if (StrEqual(classname, "boomer"))
    {
        switch (hitgroup)
        {
            case 1: return g_cvBoomerHead.FloatValue;
            case 2: return g_cvBoomerChest.FloatValue;
            case 3: return g_cvBoomerBody.FloatValue;
            case 4: return g_cvBoomerArm.FloatValue;
            case 5: return g_cvBoomerArm.FloatValue;
            case 6: return g_cvBoomerLeg.FloatValue;
            case 7: return g_cvBoomerLeg.FloatValue;
            default: return 1.0;
        }
    }
    else if (StrEqual(classname, "spitter"))
    {
        switch (hitgroup)
        {
            case 0: return g_cvSpitterBody.FloatValue;  //扣税0是身体
            case 1: return g_cvSpitterHead.FloatValue;  //口水1是头
            case 2: return g_cvSpitterArm.FloatValue;    //2手
            case 3: return g_cvSpitterArm.FloatValue;   //3手
            case 4: return g_cvSpitterLeg.FloatValue;   //4腿
            case 5: return g_cvSpitterLeg.FloatValue;   //5腿
            default: return 1.0;
        }
    }

    return 1.0;
}

//伤害计算
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_cvPluginEnabled.BoolValue || !IsSurvivor(attacker) || !IsInfected(victim))
        return Plugin_Continue;

    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 伤害: %.1f", damage);
    }

    // 获取武器信息，确保只对允许的武器进行限制
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)
        return Plugin_Continue;

    char weaponName[32];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName));

    if (!IsSniperWeapon(weaponName))
        return Plugin_Continue;

    //获取特感当前血量
    int health = GetEntProp(victim, Prop_Data, "m_iHealth");
    float maxAllowedDamage = float(health) + 1.0;   //特感当前血量+1

    //伤害限制
    if (damage > maxAllowedDamage)
    {
        damage = maxAllowedDamage;
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 伤害溢出,已限制伤害为: %.1f", damage);
        }
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

//是否为特感
bool IsInfected(int client)
{
    return IsValidClient(client) && GetClientTeam(client) == 3;
}

//是否为生还
bool IsSurvivor(int client)
{
    return IsValidClient(client) && GetClientTeam(client) == 2;
}

//有效客户端
bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

//武器类名
bool IsSniperWeapon(const char[] weaponName)
{
    static char allowedWeapons[256];
    g_cvAllowedWeapons.GetString(allowedWeapons, sizeof(allowedWeapons));

    //使用ExplodeString分割武器列表
    static char weaponList[32][32];
    int weaponCount = ExplodeString(allowedWeapons, ",", weaponList, sizeof(weaponList), sizeof(weaponList[]));

    //遍历分割后的武器列表来检查
    for (int i = 0; i < weaponCount; i++)
    {
        TrimString(weaponList[i]); // 移除可能的空格
        if (StrEqual(weaponName, weaponList[i], false))
        {
            return true;
        }
    }

    return false;
}
