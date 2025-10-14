#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <l4d2util>
#include <sdktools>
#include <sdkhooks>

#define L4D2Team_None 0
#define L4D2Team_Spectator 1
#define L4D2Team_Survivor 2
#define L4D2Team_Infected 3

int
    g_iDamageRequired,
    g_iHealPerDamage,
    g_iMaxHeal,
    g_iTempDamageRequired,
    g_iTempHealPerDamage,
    g_iTempMaxHeal,
    g_iAutoEnablePlayerCount,
    g_iDamageDealt[MAXPLAYERS + 1],
    g_iTempDamageDealt[MAXPLAYERS + 1];

bool
    g_bAllowTempHealth,
    g_bAutoEnableFeature,
    g_bPluginEnable,
    g_bCanUseMelee,
    g_bDebug;

ConVar
    g_cvPluginEnable,
    g_cvDamageRequired,
    g_cvHealPerDamage,
    g_cvMaxHeal,
    g_cvTempDamageRequired,
    g_cvTempHealPerDamage,
    g_cvTempMaxHeal,
    g_cvAllowTempHealth,
    g_cvAutoEnablePlayerCount,
    g_cvAutoEnableFeature,
    g_cvCanUseMelee,
    g_cvDebug;

public Plugin myinfo = 
{
    name = "星云猫猫生还回血",
    author = "Seiunsky Maomao",
    description = "积累生还对6只特感所造成的伤害量,到达一定阈值时转化相应回血量.限冷热武器.",
    version = "1.9",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    //cvar注册
    g_cvPluginEnable = CreateConVar("sm_heal_enabled", "1", "插件总开关.1开0关.(注意sm_heal_auto_enabled设置为1时则会根据sm_heal_auto_player的人数动态更改此项.)", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvDamageRequired = CreateConVar("sm_heal_h_required", "1000", "触发一次实血治疗所需对特感造成的伤害累计量.", FCVAR_NONE, true, 1.0);
    g_cvHealPerDamage = CreateConVar("sm_heal_h_amount", "2", "每次的实血治疗量,设置0表示不回实血.", FCVAR_NONE, true, 0.0);
    g_cvMaxHeal = CreateConVar("sm_heal_h_max", "100", "停止回实血的上限阈值.", FCVAR_NONE, true, 1.0);
    g_cvAllowTempHealth = CreateConVar("sm_heal_allow_temp", "1", "实血治疗上限阈值里是否应该包含虚血?1是0否.(启用时,虚血+实血无法超过sm_heal_h_max设置的阈值.)", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvTempDamageRequired = CreateConVar("sm_heal_t_required", "600", "触发一次虚血治疗所需对特感造成的伤害累计量.", FCVAR_NONE, true, 1.0);
    g_cvTempHealPerDamage = CreateConVar("sm_heal_t_amount", "10", "每次的虚血治疗量,设置0表示不回虚血.", FCVAR_NONE, true, 0.0);
    g_cvTempMaxHeal = CreateConVar("sm_heal_t_max", "50", "停止回虚血的上限阈值.", FCVAR_NONE, true, 0.0);

    g_cvAutoEnableFeature = CreateConVar("sm_heal_auto_enabled", "0", "是否根据玩家人数自动接管回血插件总开关?1是0否.(注意sm_heal_auto_player进行人数阈值配置.)", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvAutoEnablePlayerCount = CreateConVar("sm_heal_auto_player", "2", "玩家少于等于几人时,触发自动接管回血插件总开关?(注意需sm_heal_auto_enabled设置为1.)", FCVAR_NONE, true, 1.0);
    g_cvCanUseMelee = CreateConVar("sm_heal_melee", "0", "近战伤害能否进行回血?1是0否.", FCVAR_NONE, true, 0.0, true, 1.0);

    //debug
    g_cvDebug = CreateConVar("sm_heal_debug", "0", "调试开关.1开0关.(测试插件时才需要用到.)", FCVAR_NONE, true, 0.0, true, 1.0);

    //cvar变化监听
    g_cvPluginEnable.AddChangeHook(OnConVarChanged);
    g_cvDamageRequired.AddChangeHook(OnConVarChanged);
    g_cvHealPerDamage.AddChangeHook(OnConVarChanged);
    g_cvMaxHeal.AddChangeHook(OnConVarChanged);
    g_cvTempDamageRequired.AddChangeHook(OnConVarChanged);
    g_cvTempHealPerDamage.AddChangeHook(OnConVarChanged);
    g_cvTempMaxHeal.AddChangeHook(OnConVarChanged);
    g_cvAllowTempHealth.AddChangeHook(OnConVarChanged);
    g_cvAutoEnablePlayerCount.AddChangeHook(OnConVarChanged);
    g_cvAutoEnableFeature.AddChangeHook(OnConVarChanged);
    g_cvCanUseMelee.AddChangeHook(OnConVarChanged);
    g_cvDebug.AddChangeHook(OnConVarChanged);
    //挂钩
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    //管理命令注册
    RegAdminCmd("sm_skheal", Command_TogglePlugin, ADMFLAG_ROOT, "管理员手动进行回血插件的开关切换.(注意sm_heal_auto_enabled设置为1时则会根据sm_heal_auto的人数动态切换.)");

    //以防万一更新一遍再说
    GetConVars();
    CheckPlayerCountAndAutoEnable();

    //cfg生成,看需求
    AutoExecConfig(true, "Seiunsky_huixue");
}

//cvar
public void GetConVars()
{
    g_bPluginEnable = g_cvPluginEnable.BoolValue;
    g_iDamageRequired = g_cvDamageRequired.IntValue;
    g_iHealPerDamage = g_cvHealPerDamage.IntValue;
    g_iMaxHeal = g_cvMaxHeal.IntValue;
    g_iTempDamageRequired = g_cvTempDamageRequired.IntValue;
    g_iTempHealPerDamage = g_cvTempHealPerDamage.IntValue;
    g_iTempMaxHeal = g_cvTempMaxHeal.IntValue;
    g_bAllowTempHealth = g_cvAllowTempHealth.BoolValue;
    g_iAutoEnablePlayerCount = g_cvAutoEnablePlayerCount.IntValue;
    g_bAutoEnableFeature = g_cvAutoEnableFeature.BoolValue;
    g_bCanUseMelee = g_cvCanUseMelee.BoolValue;
    g_bDebug = g_cvDebug.BoolValue;
}

//cvar变化回调
public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetConVars();
    CheckPlayerCountAndAutoEnable();

    if (g_bDebug)
    {
        PrintToChatAll("[!] cvar发生变化,触发OnConVarChanged.");
    }
}

//插件开关切换
public Action Command_TogglePlugin(int i, int args)
{
    g_bPluginEnable = !g_bPluginEnable;
    g_cvPluginEnable.SetBool(g_bPluginEnable);
    ReplyToCommand(i, "\x04回血插件: \x05%s", g_bPluginEnable ? "启用" : "禁用");
    return Plugin_Handled;
}

//检查是否需要自动开关插件,只计算生还玩家数量
public void CheckPlayerCountAndAutoEnable()
{
    //是否允许自动开关
    if (!g_bAutoEnableFeature) return;
    //初始化为0并统计生还玩家
    int realPlayers = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsSurvivorPlayer(i))
        {
            realPlayers++;

            if (g_bDebug)
            {
                PrintToChatAll("[!] 生还玩家数量: %d", realPlayers);
                PrintToServer("[!] 生还玩家数量: %d", realPlayers);
            }
        }
    }
    //当生还玩家数量<=所设置阈值时,shouldEnable=1
    bool shouldEnable = (realPlayers <= g_iAutoEnablePlayerCount);
    if (shouldEnable != g_bPluginEnable)
    {
        g_bPluginEnable = shouldEnable;
        g_cvPluginEnable.SetBool(shouldEnable);
        PrintToChatAll("\x01[!] \x04回血插件已:\x05%s\x04.", shouldEnable ? "启用" : "关闭");
    }
}

//玩家加入,换队,退出服务器时都会触发
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    /*
    //旧语法
    int i = GetClientOfUserId(GetEventInt(event, "userid"));
    int oldTeam = GetEventInt(event, "oldteam");
    int newTeam = GetEventInt(event, "team");
    */
    int i = GetClientOfUserId(event.GetInt("userid"));
    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    
    //过滤掉ai特感
    if (IsFakeClient(i) && IsClientInGame(i) && ((oldTeam == 3) || (newTeam == 3)))
    {
        if (g_bDebug)
        {
            PrintToChatAll("[!] [%N]是AI特感,直接返回. 旧队伍: %d, 新队伍: %d", i, oldTeam, newTeam);
            PrintToServer("[!] [%N]是AI特感,直接返回. 旧队伍: %d, 新队伍: %d", i, oldTeam, newTeam);
        }
        return;
    }

    g_iDamageDealt[i] = 0;
    g_iTempDamageDealt[i] = 0;
    CheckPlayerCountAndAutoEnable();

    if (g_bDebug)
    {
        PrintToChatAll("[!] 玩家[%N]触发Event_PlayerTeam. 旧队伍: %d, 新队伍: %d", i, oldTeam, newTeam);
        PrintToServer("[!] 玩家[%N]触发Event_PlayerTeam. 旧队伍: %d, 新队伍: %d", i, oldTeam, newTeam);
    }
}

//特感受伤事件,用于获取积累的伤害量
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    //插件是否启用
    if (!g_bPluginEnable) return;
    /*
    //旧语法
    int victim = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    */
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    //对象是否正确
    if (!IsAliveSurvivor(attacker)) return;
    if (!IsValidSpecialInfected(victim)) return;
    //自残不算
    if (!attacker || attacker == victim) return;

    //武器限制
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    //转化布尔值来判断
    bool isFirearm = IsFirearm(weapon);
    bool isMelee = IsMeleeWeapon(weapon);
    //三元运算,g_bCanUseMelee开启则允许近战伤害
    bool shouldProcess = (g_bCanUseMelee) ? (isFirearm || isMelee) : (isFirearm);

    if (shouldProcess)
    {
        //获取伤害量
        //int damage = GetEventInt(event, "dmg_health");    //旧语法
        int damage = event.GetInt("dmg_health");
        //伤害量为0不需要计算
        if (damage <= 0) return;
        //定义newdamage
        int newdamage;
        
        //近战不需要额外调整,游戏本身就做调整了
        if (isMelee)
        {
            newdamage = damage;
            if (g_bDebug)
            {
                PrintToChatAll("[!] 近战使用原始伤害: %d HP.", damage);
            }
        }
        else
        {
            //热武器需要防溢出
            int infHealth = GetEntProp(victim, Prop_Send, "m_iHealth");
            newdamage = GetDamage2(damage, infHealth);
        }
        
        //最后回调处理
        ProcessHealing(attacker, newdamage);
    }
}

//防溢出调整
int GetDamage2(int damage, int infHealth)
{
    //三元运算,damage > infHealth就需要调整
    int damage2 = (damage > infHealth) ? infHealth : damage;
    
    if (g_bDebug && damage != damage2)
    {
        PrintToChatAll("[!] 触发防溢出: %d → %d [特感剩余: %d HP.]", damage, damage2, infHealth);
    }

    return damage2;
}

//伤害量处理
public void ProcessHealing(int attacker, int newdamage)
{
    if (g_iHealPerDamage > 0)
    {
        //生还对特感造成的累计伤害量
        g_iDamageDealt[attacker] += newdamage;
        //治疗次数 = 累计伤害 除以 触发一次治疗所需伤害累计量
        int healTimes = g_iDamageDealt[attacker] / g_iDamageRequired;

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]对特感累计伤害量 - 实血: %d Dmg.", attacker, g_iDamageDealt[attacker]);
        }

        //实血治疗触发
        if(healTimes > 0)
        {
            int AddMHealth = healTimes * g_iHealPerDamage;
            HealHealth(attacker, AddMHealth);
            
            //剩余积累
            g_iDamageDealt[attacker] %= g_iDamageRequired;
            
            if (g_bDebug)
            {
                PrintToChatAll("[!] 实血治疗后的伤害量积累残存: %d HP.", g_iDamageDealt[attacker]);
            }
        }
    }

    if (g_iTempHealPerDamage > 0)
    {
        //生还对特感造成的累计伤害量
        g_iTempDamageDealt[attacker] += newdamage;
        //治疗次数 = 累计伤害 除以 触发一次治疗所需伤害累计量
        int tempHealTimes = g_iTempDamageDealt[attacker] / g_iTempDamageRequired;

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]对特感累计伤害量 - 虚血: %d Dmg.", attacker, g_iTempDamageDealt[attacker]);
        }

        //虚血治疗触发
        if(tempHealTimes > 0)
        {
            int AddTHealth = tempHealTimes * g_iTempHealPerDamage;
            HealTempHealth(attacker, AddTHealth);
            
            //剩余积累
            g_iTempDamageDealt[attacker] %= g_iTempDamageRequired;
            
            if (g_bDebug)
            {
                PrintToChatAll("[!] 虚血治疗后的伤害量积累残存: %d HP.", g_iTempDamageDealt[attacker]);
            }
        }
    }
}

//实血治疗处理,以防万一全用浮点数
public void HealHealth(int attacker, int AddMHealth)
{
    //非生还则返回
    if (!IsAliveSurvivor(attacker)) return;
    
    //实血
    float currentHealth = float(GetEntProp(attacker, Prop_Send, "m_iHealth"));
    //虚血
    float tempHealth = L4D_GetTempHealth(attacker);
    //停止回实血的上限阈值
    float maxheal = float(g_iMaxHeal);

    //总血量,根据是否启用计算虚血设置而会有所不同
    float totalHealth = currentHealth + (g_bAllowTempHealth ? tempHealth : 0.0);
    //不能超出设置的最大治疗量限制或者100血限制
    //if (totalHealth >= maxheal || totalHealth >= 100) return;
    if (totalHealth >= maxheal) return;      //放开100血限制会好些,反正一般g_iMaxHeal设置100就完事了

    //可治疗血量<=0也说明不需要处理
    float availableHeal = maxheal - totalHealth;
    if (availableHeal <= 0.0) return;

    //最后一步再计算需要回多少血,需要防溢出
    float actualHeal = float(AddMHealth);
    if (actualHeal > availableHeal)
    {
        actualHeal = availableHeal;
    }
    
    //直接设置，简单粗暴：新的实血量 = 旧实血量 + 需要回的实血量
    float newHealth = currentHealth + actualHeal;
    if (newHealth <= maxheal)
    {
        SetEntProp(attacker, Prop_Send, "m_iHealth", RoundToNearest(newHealth));

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]获得实血治疗量: %.1f HP, 治疗后实血: %.1f HP.", attacker, actualHeal, newHealth);
        }
    }
    else    //一般不会执行到这里,但还是做个保障
    {
        SetEntProp(attacker, Prop_Send, "m_iHealth", maxheal);

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]获得实血治疗,但原治疗血量导致生还总实血量大于%.1f. | 直接设置实血量=%.1f即可.", attacker, maxheal, maxheal);
        }
    }
}

//虚血治疗处理
public void HealTempHealth(int attacker, int AddTHealth)
{
    //非生还则返回
    if (!IsAliveSurvivor(attacker)) return;
    
    //虚血
    float tempHealth = L4D_GetTempHealth(attacker);
    //停止回虚血的上限阈值
    float tempmaxheal = float(g_iTempMaxHeal);
    
    //不能超出最大虚血治疗量限制
    if (tempHealth >= tempmaxheal) return;

    //可治疗的虚血量
    float availableTempHeal = tempmaxheal - tempHealth;
    if (availableTempHeal <= 0.0) return;

    //计算实际虚血治疗量,防溢出处理
    float actualTempHeal = float(AddTHealth);
    if (actualTempHeal > availableTempHeal)
    {
        actualTempHeal = availableTempHeal;
    }
    
    //设置新的虚血量
    float newTempHealth = tempHealth + actualTempHeal;
    if (newTempHealth <= tempmaxheal)
    {
        L4D_SetTempHealth(attacker, newTempHealth);

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]获得虚血治疗量: %.1f HP. 治疗后虚血: %.1f HP.", attacker, actualTempHeal, newTempHealth);
        }
    }
    else    //一般不会执行到这里,但还是做个保障
    {
        L4D_SetTempHealth(attacker, tempmaxheal);

        if (g_bDebug)
        {
            PrintToChatAll("[!] 玩家[%N]获得虚血治疗,但原治疗血量导致生还总虚血量大于%.1f. | 直接设置虚血量=%.1f即可.", attacker, tempmaxheal, tempmaxheal);
        }
    }
}

//有效客户端,特感生还均可
bool IsValidClient(int i)
{
    return (IsValidClientIndex(i) && IsClientInGame(i) && !IsClientSourceTV(i) && !IsClientReplay(i));
}

/*
//特感机器人
bool IsInfectedBot(int i)
{
    return (IsValidClient(i) && IsFakeClient(i) && IsInfected(i));
}
*/

//生还玩家,死活不重要,不能是机器人
bool IsSurvivorPlayer(int i)
{
    return (IsValidClient(i) && !IsFakeClient(i) && IsSurvivor(i));
}

//活着的生还,机器人也算
bool IsAliveSurvivor(int i)
{
    return (IsValidClient(i) && IsSurvivor(i) && IsPlayerAlive(i));
}

//除克和妹外的特感
bool IsValidSpecialInfected(int i)
{
    return (IsValidClient(i) && IsInfected(i) && GetInfectedClass(i) >= 1 && GetInfectedClass(i) <= 6);
}

//是近战,包括电锯
bool IsMeleeWeapon(const char[] weapon)
{
    return (StrContains(weapon, "melee") != -1 || StrEqual(weapon, "chainsaw"));
}

//是枪械类武器,但限制以下这些
bool IsFirearm(const char[] weapon)
{
    return (StrContains(weapon, "pistol") != -1 ||
                StrContains(weapon, "pistol_magnum") != -1 ||
                StrContains(weapon, "rifle_m60") != -1 ||
                StrContains(weapon, "smg") != -1 ||
                StrContains(weapon, "smg_silenced") != -1 ||
                StrContains(weapon, "smg_mp5") != -1 ||
                StrContains(weapon, "rifle") != -1 ||
                StrContains(weapon, "rifle_desert") != -1 ||
                StrContains(weapon, "rifle_ak47") != -1 ||
                StrContains(weapon, "rifle_sg552") != -1 ||
                StrContains(weapon, "pumpshotgun") != -1 ||
                StrContains(weapon, "shotgun_chrome") != -1 ||
                StrContains(weapon, "shotgun_spas") != -1 ||
                StrContains(weapon, "autoshotgun") != -1 ||
                StrContains(weapon, "sniper_military") != -1 ||
                StrContains(weapon, "sniper_scout") != -1 ||
                StrContains(weapon, "sniper_awp") != -1 ||
                StrContains(weapon, "hunting_rifle") != -1);
}