#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "2.0.0"

ConVar g_cvPluginEnabled;
ConVar g_cvDamageOnControl;
ConVar g_cvDelayTime;
ConVar g_cvGodDuration;
ConVar g_cvEnableTakeDamage;

int g_iDamageOnControl;

float g_fDelayTime;
float g_fGodDuration;

bool g_bPluginEnabled;
bool g_bEnableTakeDamage;
bool g_bIgnoreAbility[MAXPLAYERS + 1];

enum ZombieClass
{
    ZC_None,
    ZC_Smoker,
    ZC_Boomer,
    ZC_Hunter,
    ZC_Spitter,
    ZC_Jockey,
    ZC_Charger,
    ZC_Tank
}

StringMap g_hTimerMap;
StringMap g_hGodModePlayers;

public Plugin myinfo = 
{
    name = "星云猫猫1v1",
    author = "Seiunsky Maomao",
    description = "生还被控时,扣血解控.类似于1v1eq的效果,灵感也来源于此.",
    version = PLUGIN_VERSION,
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

//这个那个
public void OnPluginStart()
{
    g_cvPluginEnabled = CreateConVar("sm_sicontrol_enabled", "1", "插件开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvDamageOnControl = CreateConVar("sm_sicontrol_damage", "25", "解控扣生还多少血?", FCVAR_NONE, true, 0.0, true, 999.0);
    g_cvDelayTime = CreateConVar("sm_sicontrol_delay", "1.0", "几秒后解控?", FCVAR_NONE, true, 0.1, true, 999.0);
    g_cvGodDuration = CreateConVar("sm_sicontrol_god_duration", "10", "生还解控后有几秒无敌?", FCVAR_NONE, true, 0.1, true, 999.0);
    g_cvEnableTakeDamage = CreateConVar("sm_sims_enable", "1", "是否移除特感对生还伤害?1是0否.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_hTimerMap = new StringMap();
    g_hGodModePlayers = new StringMap();
    
    HookEvent("tongue_grab", Event_ControlStart);
    HookEvent("tongue_release", Event_ControlEnd);
    HookEvent("lunge_pounce", Event_ControlStart);
    HookEvent("pounce_end", Event_ControlEnd);
    HookEvent("jockey_ride", Event_ControlStart);
    HookEvent("jockey_ride_end", Event_ControlEnd);
    HookEvent("charger_pummel_start", Event_ControlStart);
    HookEvent("charger_pummel_end", Event_ControlEnd);
    HookEvent("player_death", Event_PlayerDeath);
    
    HookConVarChange(g_cvPluginEnabled, OnConVarChanged);
    HookConVarChange(g_cvDamageOnControl, OnConVarChanged);
    HookConVarChange(g_cvDelayTime, OnConVarChanged);
    HookConVarChange(g_cvGodDuration, OnConVarChanged);
    HookConVarChange(g_cvEnableTakeDamage, OnConVarChanged);

    UpdateConVars();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
    }
    
    //AutoExecConfig(true, "Seiunsky_1v1");
}

//cvar回调
void UpdateConVars()
{
    g_bPluginEnabled = g_cvPluginEnabled.BoolValue;
    g_iDamageOnControl = g_cvDamageOnControl.IntValue;
    g_fDelayTime = g_cvDelayTime.FloatValue;
    g_fGodDuration = g_cvGodDuration.FloatValue;
    g_bEnableTakeDamage = g_cvEnableTakeDamage.BoolValue;
}

//cvar变化
public void OnConVarChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
    UpdateConVars();
}

//进服时挂钩
public void OnClientPutInServer(int i)
{
    if (g_bPluginEnabled && g_bEnableTakeDamage)        //全部满足true就会挂钩
    {
        SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

//特感对生还伤害，生还受到伤害时触发的
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_bPluginEnabled || !g_bEnableTakeDamage)      //只满足其一个false就会执行返回
        return Plugin_Continue;
    
    int real_attacker = GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity");
    if (real_attacker == -1) 
        real_attacker = attacker;
    
    if (IsValidSurvivor(victim) && IsSpecialInfected(real_attacker))    //注：这些特感里不包括口水和胖子
    {
        damage = 0.0;   //设置伤害为0
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

//监听特感控制
//舌
public Action L4D_OnGrabWithTongue(int victim, int attacker)
{
    if (g_bIgnoreAbility[victim])
        return Plugin_Handled;

    return Plugin_Continue;
}

//憨
public Action L4D2_OnPounceTarget(int victim, int attacker)
{
    if (g_bIgnoreAbility[victim])
        return Plugin_Handled;

    return Plugin_Continue;
}

//猴
public Action L4D2_OnJockeyRide(int victim, int attacker)
{
    if (g_bIgnoreAbility[victim])
        return Plugin_Handled;

    return Plugin_Continue;
}

//牛
public Action L4D2_OnStartCarryingVictim(int victim, int attacker)
{
    if (g_bIgnoreAbility[victim])
        return Plugin_Handled;

    return Plugin_Continue;
}

//特感控制事件
public void Event_ControlStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bPluginEnabled) return;
    
    int victim = GetClientOfUserId(event.GetInt("victim"));
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsValidSurvivor(victim) || !IsSpecialInfected(attacker)) return;

    // 无论是否进入无敌状态都要创建计时器, 防止无敌计时一瞬间被控计时出现bug
    char sKey[32];
    FormatEx(sKey, sizeof(sKey), "%d-%d", GetClientUserId(attacker), GetClientUserId(victim));
    if (g_hTimerMap.ContainsKey(sKey)) return;
    
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(attacker));
    dp.WriteCell(GetClientUserId(victim));
    Handle hTimer = CreateTimer(g_fDelayTime, Timer_DelayedPunish, dp);
    g_hTimerMap.SetValue(sKey, hTimer);
}

//特感控制结束，取消计时器
public void Event_ControlEnd(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));

    if (attacker <= 0 || victim <= 0) return;
    
    char sKey[32];
    FormatEx(sKey, sizeof(sKey), "%d-%d", GetClientUserId(attacker), GetClientUserId(victim));
    
    Handle hTimer;
    if (g_hTimerMap.GetValue(sKey, hTimer))
    {
        KillTimer(hTimer);
        g_hTimerMap.Remove(sKey);
    }
}

//延迟扣血计时器回调
public Action Timer_DelayedPunish(Handle timer, DataPack dp)
{
    dp.Reset();
    int attacker = GetClientOfUserId(dp.ReadCell());
    int victim = GetClientOfUserId(dp.ReadCell());
    delete dp;

    char sKey[32];
    FormatEx(sKey, sizeof(sKey), "%d-%d", GetClientUserId(attacker), GetClientUserId(victim));
    g_hTimerMap.Remove(sKey);

    if (!IsValidPunishTarget(attacker, victim)) return Plugin_Stop;
    
    ApplyPunishment(attacker, victim);
    return Plugin_Continue;
}

//扣血系统,以及播报特感剩余血量,铁锅提供的了好思路捏
void ApplyPunishment(int attacker, int victim)
{
    int si_health = 0;
    if(IsPlayerAlive(attacker))
    {
        si_health = GetEntProp(attacker, Prop_Data, "m_iHealth");
        ForcePlayerSuicide(attacker);
        if(IsPlayerAlive(attacker))
        {
            SlapPlayer(attacker, 0, true);
            si_health = 0;
        }
    }

    float tempHealth = L4D_GetTempHealth(victim);
    int permHealth = GetEntProp(victim, Prop_Send, "m_iHealth");
    int totalDamage = g_iDamageOnControl;
    
    //优先扣虚血
    if(tempHealth > 0.0)
    {
        float damageFloat = float(totalDamage);
        float newTemp = tempHealth - damageFloat;
        
        if(newTemp < 0.0)
        {
            totalDamage = RoundToNearest(damageFloat - tempHealth);
            newTemp = 0.0;
        }
        else
        {
            totalDamage = 0;
        }
        L4D_SetTempHealth(victim, newTemp);
    }
    
    //剩余血量不够扣时，直接处死生还
    if(totalDamage > 0)
    {
        int newPerm = permHealth - totalDamage;
        if(newPerm <= 0)
        {
            ForcePlayerSuicide(victim);
        }
        else
        {
            SetEntProp(victim, Prop_Send, "m_iHealth", newPerm);
        }
    }

    int current_perm = GetEntProp(victim, Prop_Send, "m_iHealth");
    float current_temp = L4D_GetTempHealth(victim);
    
    //播报
    PrintToChat(victim, "\x04[!]\x01 特感还剩余 \x05%d \x01HP \x04| \x01您还剩余 \x05%d \x01HP \x04+ \x05%.0f \x01DP", 
        si_health, 
        current_perm, 
        current_temp
    );

    //如果真的出现了生还被控时还是无敌的状态
    if(IsValidSurvivor(victim) && g_fGodDuration > 0.0)
    {
        // 则，先移除可能存在的旧无敌状态
        char sUserID[12];
        IntToString(GetClientUserId(victim), sUserID, sizeof(sUserID));
        g_hGodModePlayers.Remove(sUserID);
        
        // 然后再强制应用新无敌状态，堆史
        ApplyGodMode(victim);
    }
}

//无敌
void ApplyGodMode(int b)
{
    SetEntProp(b, Prop_Data, "m_takedamage", 0);
    SetEntProp(b, Prop_Send, "m_glowColorOverride", 0x00BFFF); //没法搞漂亮的颜色真可惜
    SetEntProp(b, Prop_Send, "m_iGlowType", 3);
    SetEntProp(b, Prop_Data, "m_CollisionGroup", 2);   //取消碰撞

    g_bIgnoreAbility[b] = true;
    
    char sUserID[12];
    IntToString(GetClientUserId(b), sUserID, sizeof(sUserID));
    g_hGodModePlayers.SetValue(sUserID, true);
    
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(b));
    CreateTimer(g_fGodDuration, Timer_RemoveGodMode, dp);

    //打印出来告知
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && 
            (i == b || GetClientTeam(i) == 3 || GetClientTeam(i) == 1))
        {
            PrintToChat(i, "\x04[解控保护]\x01 生还无敌效果将持续: %.1f秒", g_fGodDuration);
        }
    }
}

//移除无敌
public Action Timer_RemoveGodMode(Handle timer, DataPack dp)
{
    dp.Reset();
    int b = GetClientOfUserId(dp.ReadCell());
    delete dp;

    if(IsValidSurvivor(b))
    {
        char sUserID[12];
        IntToString(GetClientUserId(b), sUserID, sizeof(sUserID));
        g_hGodModePlayers.Remove(sUserID);
        
        SetEntProp(b, Prop_Send, "m_iGlowType", 0);
        SetEntProp(b, Prop_Data, "m_takedamage", 2);
        
        SetEntProp(b, Prop_Data, "m_CollisionGroup", 5);   //恢复碰撞
        
        g_bIgnoreAbility[b] = false;
        
        //只打印信息给生还本人/特感/旁观，不打印信息给其他生还
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && 
                (i == b || GetClientTeam(i) == 3 || GetClientTeam(i) == 1))
            {
                PrintToChat(i, "\x04[解控保护]\x01 生还无敌效果已消失");
            }
        }
    }
    return Plugin_Continue;
}

//玩家死亡事件处理
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int a = GetClientOfUserId(event.GetInt("userid"));
    //都强制清除状态
    char sUserID[12];
    IntToString(GetClientUserId(a), sUserID, sizeof(sUserID));
    g_hGodModePlayers.Remove(sUserID);
    g_bIgnoreAbility[a] = false;
    
    // 额外再清理计时器
    StringMapSnapshot snapshot = g_hTimerMap.Snapshot();
    for (int i = 0; i < snapshot.Length; i++)
    {
        char sKey[32];
        snapshot.GetKey(i, sKey, sizeof(sKey));
        if (StrContains(sKey, "%N", false) != -1 && StrContains(sKey, "%N", false) != -1)
        {
            Handle hTimer;
            if (g_hTimerMap.GetValue(sKey, hTimer))
            {
                KillTimer(hTimer);
                g_hTimerMap.Remove(sKey);
            }
        }
    }
    delete snapshot;
}

// 玩家断开连接时清理
public void OnClientDisconnect(int i)
{
    SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);

    char sUserID[12];
    IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
    g_hGodModePlayers.Remove(sUserID);
    g_bIgnoreAbility[i] = false;     //取消阻止特感控制
}

//地图结束时清理
public void OnMapEnd()
{
    // 重置 g_bIgnoreAbility
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bIgnoreAbility[i] = false;
    }

    // 清空计时器和无敌状态记录
    StringMapSnapshot snapshot = g_hTimerMap.Snapshot();
    for (int i = 0; i < snapshot.Length; i++)
    {
        char sKey[32];
        snapshot.GetKey(i, sKey, sizeof(sKey));
        
        Handle hTimer;
        if (g_hTimerMap.GetValue(sKey, hTimer))
        {
            KillTimer(hTimer);
        }
    }
    g_hTimerMap.Clear();
    delete snapshot;

    g_hGodModePlayers.Clear(); // 清空无敌状态记录
}

//生还判断
bool IsValidSurvivor(int i)
{
    return i > 0 && 
           i <= MaxClients && 
           IsClientInGame(i) && 
           GetClientTeam(i) == 2 && 
           IsPlayerAlive(i);
}

//4只控制型特感判断
bool IsSpecialInfected(int i)
{
    ZombieClass zClass = view_as<ZombieClass>(GetEntProp(i, Prop_Send, "m_zombieClass"));
    return (zClass == ZC_Smoker || 
            zClass == ZC_Hunter || 
            zClass == ZC_Jockey || 
            zClass == ZC_Charger);
}

//被控判断
bool IsValidPunishTarget(int attacker, int victim)  //惩罚？算是吧。。我英语不太好
{
    return IsSpecialInfected(attacker) && 
           IsValidSurvivor(victim) && 
           IsPlayerAlive(attacker) && 
           IsPlayerAlive(victim);
}

//先这样再那样插件清理
public void OnPluginEnd()
{
    UnhookEvent("tongue_grab", Event_ControlStart);
    UnhookEvent("tongue_release", Event_ControlEnd);
    UnhookEvent("lunge_pounce", Event_ControlStart);
    UnhookEvent("pounce_end", Event_ControlEnd);
    UnhookEvent("jockey_ride", Event_ControlStart);
    UnhookEvent("jockey_ride_end", Event_ControlEnd);
    UnhookEvent("charger_pummel_start", Event_ControlStart);
    UnhookEvent("charger_pummel_end", Event_ControlEnd);
    UnhookEvent("player_death", Event_PlayerDeath);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }

    delete g_hTimerMap;
    delete g_hGodModePlayers;
}