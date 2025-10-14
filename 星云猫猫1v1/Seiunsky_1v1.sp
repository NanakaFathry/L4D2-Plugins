#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d2util>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define L4D2Team_None 0
#define L4D2Team_Spectator 1
#define L4D2Team_Survivor 2
#define L4D2Team_Infected 3

ConVar 
    g_cvPluginEnabled,
    g_cvDamageOnControl,
    g_cvDelayTime,
    g_cvGodDuration,
    g_cvEnableTakeDamage;

int
    g_iDamageOnControl;

float
    g_fDelayTime,
    g_fGodDuration;

bool
    g_bPluginEnabled,
    g_bEnableTakeDamage,
    g_bIgnoreAbility[MAXPLAYERS + 1],
    g_bIsControlled[MAXPLAYERS + 1];

StringMap
    g_hTimerMap,
    g_hGodModePlayers;

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

public Plugin myinfo = 
{
    name = "星云猫猫1v1",
    author = "Seiunsky Maomao",
    description = "生还被控时,扣血解控.类似于1v1eq的效果,灵感也来源于此.",
    version = "2.0.3",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

//这个那个
public void OnPluginStart()
{
    g_cvPluginEnabled = CreateConVar("sm_sicontrol_enabled", "1", "插件开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvDamageOnControl = CreateConVar("sm_sicontrol_damage", "25", "解控扣生还多少血?", FCVAR_NONE, true, 0.0, true, 999.0);
    g_cvDelayTime = CreateConVar("sm_sicontrol_delay", "1.0", "几秒后解控?", FCVAR_NONE, true, 0.1, true, 999.0);
    g_cvGodDuration = CreateConVar("sm_sicontrol_god_duration", "4.0", "生还解控后有几秒无敌?", FCVAR_NONE, true, 0.1, true, 999.0);
    g_cvEnableTakeDamage = CreateConVar("sm_sims_enable", "1", "是否移除特感对生还的伤害?1是0否.", FCVAR_NONE, true, 0.0, true, 1.0);

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
    HookEvent("player_team", Event_PlayerTeam);

    g_cvPluginEnabled.AddChangeHook(OnConVarChanged);
    g_cvDamageOnControl.AddChangeHook(OnConVarChanged);
    g_cvDelayTime.AddChangeHook(OnConVarChanged);
    g_cvGodDuration.AddChangeHook(OnConVarChanged);
    g_cvEnableTakeDamage.AddChangeHook(OnConVarChanged);

    UpdateConVars();
    
    AutoExecConfig(true, "Seiunsky_1v1");
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

//这样挂钩靠谱些
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int i = GetClientOfUserId(event.GetInt("userid"));
    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    //生还特感挂钩
    if (newTeam >= 2)
    {
        SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        //PrintToChatAll("[Debug] [%N]成功挂钩OnTakeDamage!", i);
    }
    //切旁观脱钩
    if (newTeam == 1 && oldTeam >= 2)
    {
        SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        //PrintToChatAll("[Debug] [%N]成功脱钩OnTakeDamage!", i);
    }
}

//特感对生还伤害
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_bPluginEnabled || !g_bEnableTakeDamage) return Plugin_Continue;

    if (IsValidSurvivor2(victim) && IsSpecialInfected(attacker))
    {
        //PrintToChatAll("[Debug] [%N]攻击[%N]伤害类型[%d].", attacker, victim, damagetype);
        damage = 0.0;
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
    if (!IsValidSurvivor2(victim) || !IsSpecialInfected(attacker)) return;

    //如果生还已被控,则返回
    //if (g_bIsControlled[victim]) return;

    if (g_bIsControlled[victim])
    {
        //PrintToChatAll("[Debug] 控制标记更新为:true | 但再次触发Event_ControlStart,直接返回.");
        return;
    }

    //确认无误后再执行下一步
    //获取双方唯一的键名（GetClientUserId）
    char sKey[32];
    FormatEx(sKey, sizeof(sKey), "%d-%d", GetClientUserId(attacker), GetClientUserId(victim));
    //如果已有相同控制事件的计时器，则返回
    if (g_hTimerMap.ContainsKey(sKey)) return;
    //否则，则储存起来当标识
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(attacker));
    dp.WriteCell(GetClientUserId(victim));
    //计时器创建,即:sm_sicontrol_delay设置的倒计时
    //计时器结束后进入扣血函数
    Handle hTimer = CreateTimer(g_fDelayTime, Timer_DelayedPunish, dp);
    //计时器句柄与键名关联,存入g_hTimerMap中
    g_hTimerMap.SetValue(sKey, hTimer);

    //标记生还被控
    g_bIsControlled[victim] = true;
    //PrintToChatAll("[Debug] 控制标记更新为:true");
}

//特感控制结束
//也就是说在sm_sicontrol_delay倒计时结束前如果解控,就需要取消计时器
public void Event_ControlEnd(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));

    if (!IsValidSurvivor2(victim) || !IsSpecialInfected(attacker)) return;
    if (victim <= 0 || attacker <= 0 || !IsValidSurvivor2(victim) || !IsSpecialInfected(attacker)) return;

    char sKey[32];
    FormatEx(sKey, sizeof(sKey), "%d-%d", GetClientUserId(attacker), GetClientUserId(victim));
    //彻底移除对应计时器
    //比如说被同伴解控,或被舌头控后成功反杀,被抢控等情况发生时
    Handle hTimer;
    if (g_hTimerMap.GetValue(sKey, hTimer))
    {
        KillTimer(hTimer);
        g_hTimerMap.Remove(sKey);
    }

    /*
    //强制重置生还被控标记
    g_bIsControlled[victim] = false;
    PrintToChatAll("[Debug] 控制标记更新为:false | 原因:Event_ControlEnd触发.");
    */

    //重置生还被控标记
    if (g_bIsControlled[victim])
    {
        g_bIsControlled[victim] = false;
        //PrintToChatAll("[Debug] 控制标记更新为:false | 原因:Event_ControlEnd触发,且此前为true.");
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
    
    //有虚血时
    if(totalDamage > 0)
    {
        int newPerm = permHealth - totalDamage;
        //剩余总血量不够扣时,直接处死生还,然后返回即可
        if(newPerm <= 0)
        {
            ForcePlayerSuicide(victim);
            return;
        }
        else
        {
            SetEntProp(victim, Prop_Send, "m_iHealth", newPerm);
        }
    }

    int current_perm = GetEntProp(victim, Prop_Send, "m_iHealth");
    float current_temp = L4D_GetTempHealth(victim);

    //确保无敌状态不会重复应用
    if(IsValidSurvivor2(victim))
    {
        char sUserID[12];
        IntToString(GetClientUserId(victim), sUserID, sizeof(sUserID));
        
        // 先检查是否已存在无敌状态
        bool bAlreadyGodMode;
        if(g_hGodModePlayers.GetValue(sUserID, bAlreadyGodMode) && bAlreadyGodMode)
        {
            //如果已存在无敌状态，先移除旧的
            g_hGodModePlayers.Remove(sUserID);
        }
        //再应用新的无敌状态
        ApplyGodMode(victim);
    }

    //杀死特感后应用无敌的一瞬间可能造成立马再被控的情况发生
    //因此先应用无敌再扣血
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

    //播报
    PrintToChat(victim, "\x04[!]\x01 特感还剩余 \x05%d \x01HP \x04| \x01您还剩余 \x05%d \x01HP \x04+ \x05%.0f \x01DP", 
        si_health, 
        current_perm, 
        current_temp
    );
}

//无敌
void ApplyGodMode(int b)
{
    SetEntProp(b, Prop_Data, "m_takedamage", 0);
    SetEntProp(b, Prop_Send, "m_glowColorOverride", 0x00BFFF); //没法搞漂亮的颜色真可惜
    SetEntProp(b, Prop_Send, "m_iGlowType", 3);
    SetEntProp(b, Prop_Data, "m_CollisionGroup", 2);   //取消碰撞

    g_bIgnoreAbility[b] = true;
    //PrintToChatAll("[Debug] 无敌标记更新为:true.");
    
    char sUserID[12];
    IntToString(GetClientUserId(b), sUserID, sizeof(sUserID));
    g_hGodModePlayers.SetValue(sUserID, true);
    
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(b));
    CreateTimer(g_fGodDuration, Timer_RemoveGodMode, dp);

    PrintToChatAll("\x04[解控保护]\x01 生还无敌效果将持续: %.1f秒", g_fGodDuration);
}

//移除无敌
public Action Timer_RemoveGodMode(Handle timer, DataPack dp)
{
    dp.Reset();
    int b = GetClientOfUserId(dp.ReadCell());
    delete dp;

    if(IsValidSurvivor2(b))
    {
        char sUserID[12];
        IntToString(GetClientUserId(b), sUserID, sizeof(sUserID));
        g_hGodModePlayers.Remove(sUserID);
        
        SetEntProp(b, Prop_Send, "m_iGlowType", 0);
        SetEntProp(b, Prop_Data, "m_takedamage", 2);
        
        SetEntProp(b, Prop_Data, "m_CollisionGroup", 5);   //恢复碰撞
        
        g_bIgnoreAbility[b] = false;
        //PrintToChatAll("[Debug] 无敌标记更新为:false.");
        
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

    if (!IsValidSurvivor2(a)) return;   //非生还勿扰
    
    //无敌状态清理
    char sUserID[12];
    IntToString(GetClientUserId(a), sUserID, sizeof(sUserID));
    if (g_hGodModePlayers.ContainsKey(sUserID))
    {
        g_hGodModePlayers.Remove(sUserID);
    }
    
    //无敌状态
    if (g_bIgnoreAbility[a])
    {
        g_bIgnoreAbility[a] = false;
        //PrintToChatAll("[Debug] 无敌标记更新为:false | 原因:Event_PlayerDeath触发,且此前为true.");
    }

    //控制状态
    if (g_bIsControlled[a])
    {
        g_bIsControlled[a] = false;
        //PrintToChatAll("[Debug] 控制标记更新为:false | 原因:Event_PlayerDeath触发,且此前为true.");
    }
    
    //计时器清理
    if (g_hTimerMap.Size > 0)
    {
        StringMapSnapshot snapshot = g_hTimerMap.Snapshot();
        
        for (int i = 0; i < snapshot.Length; i++)
        {
            char sKey[32];
            snapshot.GetKey(i, sKey, sizeof(sKey));
            
            // 检查键名，是否包含死亡玩家
            if (StrContains(sKey, sUserID) != -1)
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
}

//玩家断开连接时清理
public void OnClientDisconnect(int i)
{
    //无敌状态清理
    char sUserID[12];
    IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
    if (g_hGodModePlayers.ContainsKey(sUserID))
    {
        g_hGodModePlayers.Remove(sUserID);
    }
    
    //重置无敌状态
    if (g_bIgnoreAbility[i])
    {
        g_bIgnoreAbility[i] = false;
        //PrintToChatAll("[Debug] 无敌标记更新为:false | 原因:OnClientDisconnect触发,且此前为true.");
    }

    //重置控制状态
    if (g_bIsControlled[i])
    {
        g_bIsControlled[i] = false;
        //PrintToChatAll("[Debug] 控制标记更新为:false | 原因:OnClientDisconnect触发,且此前为true.");
    }
}

//地图结束时清理和重置状态
public void OnMapEnd()
{
    //计时器清理
    if (g_hTimerMap.Size > 0)
    {
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
    }

    //无敌状态清理
    if (g_hGodModePlayers.Size > 0)
    {
        g_hGodModePlayers.Clear();
    }

    //重置状态
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidSurvivor2(i)) //只需要处理生还
        {
            //无敌状态重置
            if (g_bIgnoreAbility[i])
            {
                g_bIgnoreAbility[i] = false;
                //PrintToChatAll("[Debug] 无敌标记更新为:false | 原因:OnMapEnd触发,且此前为true.");
            }
            //控制状态重置
            if (g_bIsControlled[i])
            {
                g_bIsControlled[i] = false;
                //PrintToChatAll("[Debug] 控制标记更新为:false | 原因:OnMapEnd触发,且此前为true.");
            }
        }
    }
}

//地图开始也需要简单重置状态
public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidSurvivor2(i)) //只需要处理生还
        {
            //无敌状态重置
            if (g_bIgnoreAbility[i])
            {
                g_bIgnoreAbility[i] = false;
                //PrintToChatAll("[Debug] 无敌标记更新为:false | 原因:OnMapStart触发,且此前为true.");
            }
            //控制状态重置
            if (g_bIsControlled[i])
            {
                g_bIsControlled[i] = false;
                //PrintToChatAll("[Debug] 控制标记更新为:false | 原因:OnMapStart触发,且此前为true.");
            }
        }
    }
}

//有效客户端,特感生还均可
bool IsValidClient(int i)
{
    return (IsValidClientIndex(i) && IsClientInGame(i) && !IsClientSourceTV(i) && !IsClientReplay(i));
}

//生还判断,无论生死
bool IsValidSurvivor2(int i)
{
    return IsValidClient(i) && IsSurvivor(i);
}

//4只控制型特感判断
bool IsSpecialInfected(int i)
{
    return (IsValidClient(i) && IsInfected(i) && (GetInfectedClass(i) == 1 || GetInfectedClass(i) == 3 || GetInfectedClass(i) == 5 || GetInfectedClass(i) == 6));
}

//有效的双方,攻击-特感,受害-生还.
bool IsValidPunishTarget(int attacker, int victim)
{
    return IsSpecialInfected(attacker) && IsValidSurvivor2(victim) && IsPlayerAlive(attacker) && IsPlayerAlive(victim);
}
