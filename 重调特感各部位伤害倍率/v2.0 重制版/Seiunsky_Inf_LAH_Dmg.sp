/*
* 更新日志：
    v2.0 : 重构插件,能够更详细地设置不同枪械对于不同特感不同部位的伤害倍率,
           例如设置: sm_skwp weapon_sniper_scout charger_head 5.25 ,
           表示鸟狙(weapon_sniper_scout)这把武器针对Charger爆头伤害(charger_head)倍率由原版4倍改为5.25.
           如果其他部位/其他特感/其他武器没有设置则保持原版设定.
           
    v2.1 : 合并了我另外的Seiunsky_Inf_Ctrl_Feeling_Hurt插件功能,
           用于调节特感控住人时,除了头部外其余肢体额外受到的伤害倍率增益.
           例如设置: sm_smoker_hurt_x 1.25,
           则表示smoker在控人时,除了头部外生还打该名smoker其他肢体的伤害都额外x1.25倍.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

ConVar 
    g_cvPluginEnabled,
    g_cvDebugEnabled,
    g_cvSmokerDamageMultiplier,
    g_cvHunterDamageMultiplier,
    g_cvJockeyDamageMultiplier,
    g_cvChargerDamageMultiplier;

bool
    g_bIsGrabbingSurvivor[MAXPLAYERS + 1],
    g_bIsPouncingSurvivor[MAXPLAYERS + 1],
    g_bIsRidingSurvivor[MAXPLAYERS + 1],
    g_bIsBeatingSurvivor[MAXPLAYERS + 1];

StringMap
    g_WeaponDamageConfig;

public Plugin myinfo =
{
    name = "重调特感各部位伤害倍率[重制版]",
    author = "Seiunsky Maomao",
    description = "枪械对特感的不同部位重新设置不同伤害倍率.",
    version = "2.1",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    g_cvPluginEnabled = CreateConVar("sm_inf_lah_on", "1", "插件开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvDebugEnabled = CreateConVar("sm_inf_lah_debug", "0", "调试开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvSmokerDamageMultiplier = CreateConVar("sm_smoker_hurt_x", "1.00", "舌头控人时,除头部外其余部位受到的伤害增益.设置1.00则表示关闭此功能.", FCVAR_NOTIFY, true, 1.0);
    g_cvHunterDamageMultiplier = CreateConVar("sm_hunter_hurt_x", "1.00", "猎人控人时,除头部外其余部位受到的伤害增益.设置1.00则表示关闭此功能.", FCVAR_NOTIFY, true, 1.0);
    g_cvJockeyDamageMultiplier = CreateConVar("sm_jockey_hurt_x", "1.00", "猴子控人时,除头部外其余部位受到的伤害增益.设置1.00则表示关闭此功能.", FCVAR_NOTIFY, true, 1.0);
    g_cvChargerDamageMultiplier = CreateConVar("sm_charger_hurt_x", "1.00", "牛子控人时,除头部外其余部位受到的伤害增益.设置1.00则表示关闭此功能.", FCVAR_NOTIFY, true, 1.0);
    
    RegServerCmd("sm_skwp", Command_WeaponConfig, "添加设置枪械对于不同特感不同部位的伤害倍率配置. (sm_skwp [枪械] [特感_部位] [倍率])");

    RegAdminCmd("sm_skwp_list", Command_WeaponList, ADMFLAG_CHEATS, "列出当前全部枪械配置.");
    RegAdminCmd("sm_skwp_clear", Command_WeaponClear, ADMFLAG_CHEATS, "清除枪械配置. (!skwp_clear [枪械] / !skwp_clear all)");
    
    HookEvent("round_start", Event_RoundStart);
    HookEvent("tongue_grab", Event_TongueGrab);
    HookEvent("tongue_release", Event_TongueRelease);
    HookEvent("lunge_pounce", Event_LungePounce);
    HookEvent("pounce_end", Event_PounceEnd);
    HookEvent("jockey_ride", Event_JockeyRide);
    HookEvent("jockey_ride_end", Event_JockeyRideEnd);
    HookEvent("charger_pummel_start", Event_ChargerPummelStart);
    HookEvent("charger_pummel_end", Event_ChargerPummelEnd);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);

    g_WeaponDamageConfig = new StringMap();

    AutoExecConfig(true, "Seiunsky_Inf_LAH_Dmg");
}

public Action Command_WeaponConfig(int args)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return Plugin_Continue;
    
    //设置不对劲,戳辣
    if (args != 3)
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToServer("* 用法: sm_skwp [枪械] [特感_部位] [倍率]");
            PrintToServer("* 用例: sm_skwp weapon_sniper_scout smoker_head 4.25");
            PrintToServer("* 特感: smoker, hunter, jockey, charger, boomer, spitter");
            PrintToServer("* 部位: head, body, arm, leg");
            PrintToServer("* 部位: chest (仅限hunter,smoker,boomer这3特感.)");
        }
        return Plugin_Handled;
    }

    //设置对啦,则进入验证
    char weaponName[32], damageKey[64], damageValue[16];
    GetCmdArg(1, weaponName, sizeof(weaponName));
    GetCmdArg(2, damageKey, sizeof(damageKey));
    GetCmdArg(3, damageValue, sizeof(damageValue));

    // 验证特感部位格式
    if (!IsValidDamageKey(damageKey))
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToServer("* 无效的特感部位格式: %s", damageKey);
            PrintToServer("* 用法: [特感_部位] (例: smoker_head, hunter_body, ...)");
            PrintToServer("* 注意:部位chest仅限hunter,smoker,boomer这3特感.");
        }

        return Plugin_Handled;
    }

    float multiplier = StringToFloat(damageValue);
    if (multiplier <= 0.0)
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            //因为我在下面设置了,当没有任何的武器配置时,则赋值-1.0,并跳过处理
            PrintToServer("* 伤害倍率不能设置小于或等于0: %.2f", multiplier);
        }

        return Plugin_Handled;
    }

    //通过后则构建完整配置
    char configKey[128];
    Format(configKey, sizeof(configKey), "%s_%s", weaponName, damageKey);

    //保存到g_WeaponDamageConfig
    g_WeaponDamageConfig.SetValue(configKey, multiplier);
    
    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToServer("* 成功设置[%s]的[%s]伤害倍率为[%.2f].", weaponName, damageKey, multiplier);
    }
    
    return Plugin_Handled;
}

public Action Command_WeaponList(int i, int args)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return Plugin_Continue;
    
    StringMapSnapshot snapshot = g_WeaponDamageConfig.Snapshot();
    int size = snapshot.Length;
    
    if (size == 0)
    {
        ReplyToCommand(i, "\x04当前没有\x05[枪械-特感-伤害]\x04配置.");
        delete snapshot;
        return Plugin_Handled;
    }

    ReplyToCommand(i, "\x04当前的 \x05[枪械-特感-伤害] \x04配置有 \x01%d \x04项:", size);
    
    char configKey[128];
    float multiplier;
    
    for (int b = 0; b < size; b++)
    {
        snapshot.GetKey(b, configKey, sizeof(configKey));
        if (g_WeaponDamageConfig.GetValue(configKey, multiplier))
        {
            ReplyToCommand(b, "%s = %.2f", configKey, multiplier);
        }
    }
    
    delete snapshot;
    return Plugin_Handled;
}

public Action Command_WeaponClear(int i, int args)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return Plugin_Continue;
    
    if (args < 1)
    {
        ReplyToCommand(i, "用法: !sm_skwp_clear [枪械] (清除指定枪械的配置.)");
        ReplyToCommand(i, "用法: !sm_skwp_clear all (清除所有配置.)");
        return Plugin_Handled;
    }

    char weaponName[32];
    GetCmdArg(1, weaponName, sizeof(weaponName));

    if (StrEqual(weaponName, "all"))
    {
        g_WeaponDamageConfig.Clear();
        ReplyToCommand(i, "\x04已清除所有\x05[枪械-特感-伤害]\x04配置.");
        return Plugin_Handled;
    }

    StringMapSnapshot snapshot = g_WeaponDamageConfig.Snapshot();
    int cleared = 0;
    char configKey[128];
    
    for (int b = 0; b < snapshot.Length; b++)
    {
        snapshot.GetKey(b, configKey, sizeof(configKey));
        if (StrContains(configKey, weaponName) == 0)
        {
            g_WeaponDamageConfig.Remove(configKey);
            cleared++;
        }
    }
    
    delete snapshot;
    ReplyToCommand(i, "\x04已清除枪械\x05[%s]\x04的\x05[%d]\x04项伤害配置.", weaponName, cleared);
    
    return Plugin_Handled;
}

//特感生成事件
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return;

    int i = GetClientOfUserId(event.GetInt("userid"));

    if (IsInfected(i))
    {
        // sdkhook应该是会在特感死亡时自动取消，随后对新生成的特感重新挂钩
        SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        SDKHook(i, SDKHook_TraceAttack, OnTraceAttack);
    }
}

//玩家首次进入服务器,换图后进入重新回到服务器等都会执行这个事件
public void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsSmoker(i) && g_bIsGrabbingSurvivor[i])
    {
        g_bIsGrabbingSurvivor[i] = false;
    }

    if (IsHunter(i) && g_bIsPouncingSurvivor[i])
    {
        g_bIsPouncingSurvivor[i] = false;
    }

    if (IsJockey(i) && g_bIsRidingSurvivor[i])
    {
        g_bIsRidingSurvivor[i] = false;
    }

    if (IsCharger(i) && g_bIsBeatingSurvivor[i])
    {
        g_bIsBeatingSurvivor[i] = false;
    }
}

//回合开始时,载入地图时不会执行这个而是执行Event_PlayerConnectFull
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsSmoker(i) && g_bIsGrabbingSurvivor[i])
    {
        g_bIsGrabbingSurvivor[i] = false;
    }

    if (IsHunter(i) && g_bIsPouncingSurvivor[i])
    {
        g_bIsPouncingSurvivor[i] = false;
    }

    if (IsJockey(i) && g_bIsRidingSurvivor[i])
    {
        g_bIsRidingSurvivor[i] = false;
    }

    if (IsCharger(i) && g_bIsBeatingSurvivor[i])
    {
        g_bIsBeatingSurvivor[i] = false;
    }
}

//特感死掉
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsSmoker(i) && g_bIsGrabbingSurvivor[i])
    {
        g_bIsGrabbingSurvivor[i] = false;
    }

    if (IsHunter(i) && g_bIsPouncingSurvivor[i])
    {
        g_bIsPouncingSurvivor[i] = false;
    }

    if (IsJockey(i) && g_bIsRidingSurvivor[i])
    {
        g_bIsRidingSurvivor[i] = false;
    }

    if (IsCharger(i) && g_bIsBeatingSurvivor[i])
    {
        g_bIsBeatingSurvivor[i] = false;
    }
}

//特感被kick或者断开连接
public void OnClientDisconnect(int i)
{
    if (IsSmoker(i) && g_bIsGrabbingSurvivor[i])
    {
        g_bIsGrabbingSurvivor[i] = false;
    }

    if (IsHunter(i) && g_bIsPouncingSurvivor[i])
    {
        g_bIsPouncingSurvivor[i] = false;
    }

    if (IsJockey(i) && g_bIsRidingSurvivor[i])
    {
        g_bIsRidingSurvivor[i] = false;
    }

    if (IsCharger(i) && g_bIsBeatingSurvivor[i])
    {
        g_bIsBeatingSurvivor[i] = false;
    }
}

//舌头抓人
public void Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsSmoker(i))    //其实我觉得好像也不需要判定,但以防万一还是加上去,下面也如此
    {
        g_bIsGrabbingSurvivor[i] = true;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 舌头控人.");
        }
    }
}

//舌头放人
public void Event_TongueRelease(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsSmoker(i) && g_bIsGrabbingSurvivor[i])
    {
        g_bIsGrabbingSurvivor[i] = false;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 舌头放人.");
        }
    }
}

//猎人抓人
public void Event_LungePounce(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsHunter(i))
    {
        g_bIsPouncingSurvivor[i] = true;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 猎人控人.");
        }
    }
}

//猎人放人
public void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsHunter(i) && g_bIsPouncingSurvivor[i])
    {
        g_bIsPouncingSurvivor[i] = false;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 猎人放人.");
        }
    }
}

//猴抓人
public void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsJockey(i))
    {
        g_bIsRidingSurvivor[i] = true;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 猴子控人.");
        }
    }
}

//猴放人
public void Event_JockeyRideEnd(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsJockey(i) && g_bIsRidingSurvivor[i])
    {
        g_bIsRidingSurvivor[i] = false;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 猴子放人.");
        }
    }
}

//牛抓人
public void Event_ChargerPummelStart(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsCharger(i))
    {
        g_bIsBeatingSurvivor[i] = true;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 牛子控人.");
        }
    }
}

//牛放人
public void Event_ChargerPummelEnd(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsCharger(i) && g_bIsBeatingSurvivor[i])
    {
        g_bIsBeatingSurvivor[i] = false;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 牛子放人.");
        }
    }    
}

//获取对应枪械的伤害倍率
float GetDamageMultiplier(const char[] weaponName, const char[] classname, int hitgroup)
{
    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 枪械[%s],特感[%s],部位[%d].", weaponName, classname, hitgroup);
    }

    // 如果hitgroup为-1,表示没设置
    if (hitgroup == -1)
    {
        //是否有部位配置
        char configKeys[5][32] = {"head", "chest", "body", "arm", "leg"};
        for (int i = 0; i < 5; i++)
        {
            char configKey[128];

            //将他弄成 weaponName_classname_configKeys 的形式
            Format(configKey, sizeof(configKey), "%s_%s_%s", weaponName, classname, configKeys[i]);

            float multiplier;
            if (g_WeaponDamageConfig.GetValue(configKey, multiplier))
            {
                return 1.0;     //有配置,返回正值表示存在配置
            }
        }

        return -1.0;    //没有任何配置则为-1
    }

    // 原有的具体部位检查逻辑
    char hitgroupKey[32];
    if (!GetHitgroupKey(classname, hitgroup, hitgroupKey, sizeof(hitgroupKey)))
    {
        return -1.0;    //无效的部位
    }

    // 构建完整的配置键
    char configKey[128];

    //将他弄成 weaponName_classname_configKeys 的形式
    Format(configKey, sizeof(configKey), "%s_%s_%s", weaponName, classname, hitgroupKey);

    float multiplier;

    if (g_WeaponDamageConfig.GetValue(configKey, multiplier))
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 拥有对应[枪械-特感-伤害]配置:");
            PrintToChatAll("[debug] 配置:[%s]", configKey);
        }

        return multiplier;
    }

    return -1.0;    //没有找到配置也为-1
}

//特感受击处理
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    //插件是否开启
    if (!g_cvPluginEnabled.BoolValue)
        return Plugin_Continue;

    //确保攻击者是有效的生还,受害者是有效的特感
    if (!IsSurvivor(attacker) || !IsInfected(victim))
        return Plugin_Continue;

    //非子弹伤害不处理
    if (!(damagetype & DMG_BULLET))
        return Plugin_Continue;

    //获取攻击者当前使用的枪械实体
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)   //特殊情况也直接返回
        return Plugin_Continue;

    char weaponName[32];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName)); //枪械类名获取

    // 检查该枪械是否有任何伤害配置
    if ((!HasWeaponConfig(weaponName)) && (g_cvSmokerDamageMultiplier.FloatValue == 1.00) && (g_cvHunterDamageMultiplier.FloatValue == 1.00) && (g_cvJockeyDamageMultiplier.FloatValue == 1.00) && (g_cvChargerDamageMultiplier.FloatValue == 1.00))
    {
        //检查是否有配置
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 枪械[%s]没有伤害配置,跳过处理.", weaponName);
        }

        //没有就跳过
        return Plugin_Continue;
    }

    //调试看枪械类名
    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 当前枪械:[%s].", weaponName);
    }

    //特感类型
    char classname[32];
    if (IsInfected(victim))
    {
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
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 枚举id:[%d], 对应特感:[%s].", zombieClass, classname);
        }
        */
    }
    else
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 不是对应特感,跳过处理.");   //一般不会打印出这个
        }

        //不是对应特感则直接返回
        return Plugin_Continue;
    }

    //获取伤害倍率
    float multiplier = GetDamageMultiplier(weaponName, classname, hitgroup);
    
    // 如果都没有配置，直接返回，保持游戏默认倍率
    if ((multiplier < 0) && (g_cvSmokerDamageMultiplier.FloatValue == 1.00) && (g_cvHunterDamageMultiplier.FloatValue == 1.00) && (g_cvJockeyDamageMultiplier.FloatValue == 1.00) && (g_cvChargerDamageMultiplier.FloatValue == 1.00))
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 枪械[%s]对[%s]的部位[%d]没有配置.", weaponName, classname, hitgroup);
            PrintToChatAll("[debug] 跳过处理,将回到游戏原版默认的部位倍率.");
        }

        return Plugin_Continue;
    }

    float baseDamage = damage;

    //multiplier没设置,即multiplier < 0时,但是又有设置sm_*_hurt_x的情况
    if (multiplier < 0)
    {
        if (g_bIsGrabbingSurvivor[victim] && g_cvSmokerDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvSmokerDamageMultiplier.FloatValue;
            damage = baseDamage * multiplier2;

            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 没有配置,将按照游戏原版倍率,");
                PrintToChatAll("[debug] 再加上舌头控人时增益倍率[%.2f]", multiplier2);
            }
        }
        else if (g_bIsPouncingSurvivor[victim] && g_cvHunterDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvHunterDamageMultiplier.FloatValue;
            damage = baseDamage * multiplier2;

            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 没有配置,将按照游戏原版倍率,");
                PrintToChatAll("[debug] 再加上猎人控人时增益倍率[%.2f]", multiplier2);
            }
        }
        else if (g_bIsRidingSurvivor[victim] && g_cvJockeyDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvJockeyDamageMultiplier.FloatValue;
            damage = baseDamage * multiplier2;

            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 没有配置,将按照游戏原版倍率,");
                PrintToChatAll("[debug] 再加上猴子控人时增益倍率[%.2f]", multiplier2);
            }
        }
        else if (g_bIsBeatingSurvivor[victim] && g_cvChargerDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvChargerDamageMultiplier.FloatValue;
            damage = baseDamage * multiplier2;

            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 没有配置,将按照游戏原版倍率,");
                PrintToChatAll("[debug] 再加上牛子控人时增益倍率[%.2f]", multiplier2);
            }
        }
        else
        {
            damage = baseDamage;
            //特感不在控人状态,且没有设置任何配置
            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 没有配置,将按照游戏原版倍率,");
                PrintToChatAll("[debug] 造成原版伤害.");
            }
        }

        return Plugin_Changed;
    }

    //multiplier成功设置,即multiplier > 0时,细分是否还有设置sm_*_hurt_x的情况
    if (multiplier > 0)
    {
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

        //先移除游戏默认的部位伤害倍率
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

        //应用伤害倍率,分多组情况
        //需要根据特感控人状态,判断是否要第二次应用额外的伤害倍率
        if (g_bIsGrabbingSurvivor[victim] && g_cvSmokerDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvSmokerDamageMultiplier.FloatValue;
            damage = baseDamage * (multiplier * multiplier2);

            if (g_cvDebugEnabled.BoolValue)
            {
                float remp = multiplier * multiplier2;
                PrintToChatAll("[debug] 基础倍率[%.2f]", multiplier);
                PrintToChatAll("[debug] 舌头控人时增益倍率[%.2f]", multiplier2);
                PrintToChatAll("[debug] 最终倍率[%.2f]", remp);
            }
        }
        else if (g_bIsPouncingSurvivor[victim] && g_cvHunterDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvHunterDamageMultiplier.FloatValue;
            damage = baseDamage * (multiplier * multiplier2);

            if (g_cvDebugEnabled.BoolValue)
            {
                float remp = multiplier * multiplier2;
                PrintToChatAll("[debug] 基础倍率[%.2f]", multiplier);
                PrintToChatAll("[debug] 猎人控人时增益倍率[%.2f]", multiplier2);
                PrintToChatAll("[debug] 最终倍率[%.2f]", remp);
            }
        }
        else if (g_bIsRidingSurvivor[victim] && g_cvJockeyDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvJockeyDamageMultiplier.FloatValue;
            damage = baseDamage * (multiplier * multiplier2);

            if (g_cvDebugEnabled.BoolValue)
            {
                float remp = multiplier * multiplier2;
                PrintToChatAll("[debug] 基础倍率[%.2f]", multiplier);
                PrintToChatAll("[debug] 猴子控人时增益倍率[%.2f]", multiplier2);
                PrintToChatAll("[debug] 最终倍率[%.2f]", remp);
            }
        }
        else if (g_bIsBeatingSurvivor[victim] && g_cvChargerDamageMultiplier.FloatValue > 1 && hitgroup != 1)
        {
            float multiplier2 = g_cvChargerDamageMultiplier.FloatValue;
            damage = baseDamage * (multiplier * multiplier2);

            if (g_cvDebugEnabled.BoolValue)
            {
                float remp = multiplier * multiplier2;
                PrintToChatAll("[debug] 基础倍率[%.2f]", multiplier);
                PrintToChatAll("[debug] 牛子控人时增益倍率[%.2f]", multiplier2);
                PrintToChatAll("[debug] 最终倍率[%.2f]", remp);
            }
        }
        else
        {
            damage = baseDamage * multiplier;
            //特感不在控人状态,无需第二次应用额外伤害倍率
            if (g_cvDebugEnabled.BoolValue)
            {
                PrintToChatAll("[debug] 仅算基础倍率[%.2f]", multiplier);
            }
        }

        return Plugin_Changed;
    }
    //一般不会执行到这一步,因为倍率不允许设置小于等于0
    //按照我写的逻辑,没有配置时赋值-1.0处理
    return Plugin_Continue;
}

//受击后的伤害计算
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    //插件是否开启,或非有效生还,非有效特感
    if (!g_cvPluginEnabled.BoolValue || !IsSurvivor(attacker) || !IsInfected(victim))
        return Plugin_Continue;

    //非子弹伤害不处理
    if (!(damagetype & DMG_BULLET))
        return Plugin_Continue;

    //获取枪械信息，确保只对配置的枪械进行限制
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon == -1)
        return Plugin_Continue;

    /*
    char weaponName[32];
    GetEntityClassname(weapon, weaponName, sizeof(weaponName));
    //检查是否有配置
    if (!HasWeaponConfig(weaponName))
        return Plugin_Continue;
    */

    if (g_cvDebugEnabled.BoolValue)
    {
        PrintToChatAll("[debug] 造成[%.1f]伤害.", damage);
    }

    //获取特感当前血量
    int health = GetEntProp(victim, Prop_Data, "m_iHealth");
    float maxAllowedDamage = float(health) + 1.0;   //特感当前血量+1

    //伤害限制
    if (damage > maxAllowedDamage)
    {
        float oldDamage = damage;
        damage = maxAllowedDamage;

        if (g_cvDebugEnabled.BoolValue)
        {
            PrintToChatAll("[debug] 伤害溢出,进行限制调整:");
            PrintToChatAll("[debug] [%.1f] → [%.1f] | 特感血量: [%d]", oldDamage, damage, health);
        }

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

//检查枪械是否有配置
bool HasWeaponConfig(const char[] weaponName)
{
    //直接看g_WeaponDamageConfig
    StringMapSnapshot snapshot = g_WeaponDamageConfig.Snapshot();
    bool hasConfig = false;
    char configKey[128];
    
    for (int i = 0; i < snapshot.Length; i++)
    {
        snapshot.GetKey(i, configKey, sizeof(configKey));
        if (StrContains(configKey, weaponName) == 0)
        {
            hasConfig = true;
            break;
        }
    }

    delete snapshot;
    return hasConfig;
}

//将hitgroup转换为部位键名
bool GetHitgroupKey(const char[] classname, int hitgroup, char[] key, int keyLen)
{
    //不同特感部位判定不同,分组设置
    if (StrEqual(classname, "smoker") || StrEqual(classname, "hunter") || StrEqual(classname, "boomer"))
    {
        switch (hitgroup)
        {
            case 1: strcopy(key, keyLen, "head");
            case 2: strcopy(key, keyLen, "chest");
            case 3: strcopy(key, keyLen, "body");       //stomach
            case 4, 5: strcopy(key, keyLen, "arm");
            case 6, 7: strcopy(key, keyLen, "leg");
            default: return false;
        }
    }
    else if (StrEqual(classname, "jockey") || StrEqual(classname, "charger") || StrEqual(classname, "spitter"))
    {
        switch (hitgroup)
        {
            case 0: strcopy(key, keyLen, "body");
            case 1: strcopy(key, keyLen, "head");
            case 2, 3: strcopy(key, keyLen, "arm");
            case 4, 5: strcopy(key, keyLen, "leg");
            default: return false;
        }
    }
    else
    {
        return false;
    }

    return true;
}

//验证伤害键格式
bool IsValidDamageKey(const char[] damageKey)
{
    char parts[2][32];
    if (ExplodeString(damageKey, "_", parts, 2, 32) != 2)
        return false;
    
    //特感类型
    if (!StrEqual(parts[0], "smoker") && !StrEqual(parts[0], "hunter") && 
        !StrEqual(parts[0], "jockey") && !StrEqual(parts[0], "charger") && 
        !StrEqual(parts[0], "boomer") && !StrEqual(parts[0], "spitter"))
        return false;
    
    //各肢体部位
    if (!StrEqual(parts[1], "head") && !StrEqual(parts[1], "body") && 
        !StrEqual(parts[1], "arm") && !StrEqual(parts[1], "leg") &&
        !StrEqual(parts[1], "chest"))
        return false;

    //chest只对这3特感有效
    if (StrEqual(parts[1], "chest") && !StrEqual(parts[0], "smoker") && 
        !StrEqual(parts[0], "hunter") && !StrEqual(parts[0], "boomer"))
    {
        return false;
    }
    
    return true;
}

//是否为特感
bool IsInfected(int i)
{
    return IsValidClient(i) && GetClientTeam(i) == 3;
}

//是否为生还
bool IsSurvivor(int i)
{
    return IsValidClient(i) && GetClientTeam(i) == 2;
}

//是否为舌头
bool IsSmoker(int i)
{
    if (!IsValidClient(i) || GetClientTeam(i) != 3) return false;
    
    return (GetEntProp(i, Prop_Send, "m_zombieClass") == 1);
}

//是否为猎人
bool IsHunter(int i)
{
    if (!IsValidClient(i) || GetClientTeam(i) != 3) return false;
    
    return (GetEntProp(i, Prop_Send, "m_zombieClass") == 3);
}

//是否为猴子
bool IsJockey(int i)
{
    if (!IsValidClient(i) || GetClientTeam(i) != 3) return false;
    
    return (GetEntProp(i, Prop_Send, "m_zombieClass") == 5);
}

//是否为牛子
bool IsCharger(int i)
{
    if (!IsValidClient(i) || GetClientTeam(i) != 3) return false;
    
    return (GetEntProp(i, Prop_Send, "m_zombieClass") == 6);
}

/*
//是否为dps特感
bool IsDpsInf(int i)
{
    if (!IsValidClient(i) || GetClientTeam(i) != 3) return false;
    
    return GetEntProp(i, Prop_Send, "m_zombieClass") == 2 || GetEntProp(i, Prop_Send, "m_zombieClass") == 4;
}
*/

//是否有效客户端
bool IsValidClient(int i)
{
    return i > 0 && i <= MaxClients && IsClientInGame(i);
}