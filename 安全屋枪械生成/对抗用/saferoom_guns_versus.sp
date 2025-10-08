#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <l4d2util>
#include <l4d2lib>

#define PLUGIN_VERSION "2.0.1"

ConVar g_cvEnable;
ConVar g_cvWeapons;
ConVar g_cvCounts;
ConVar g_cvDebug;

bool g_bEnabled;
bool g_bWeaponsSpawned;
bool g_bPlayerConnected = false;
bool g_bRoundEndExecuted = false;

ArrayList g_aWeapons;
ArrayList g_aCounts;

StringMap g_WeaponNameToId;

public Plugin myinfo = 
{
    name = "[对抗]安全屋枪械生成",
    author = "Seiunsky Maomao",
    description = "在安全屋里生成对应枪械,类似于MeleeInSafeRoom插件.",
    version = PLUGIN_VERSION,
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    g_cvEnable = CreateConVar("sm_saferoom_weapons_enable", "1", "插件开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvWeapons = CreateConVar("sm_saferoom_weapons_list", "sniper_scout,smg_silenced,smg", "要生成的枪械,用逗号隔开.");
    g_cvCounts = CreateConVar("sm_saferoom_weapons_counts", "1,1,1", "各枪械生成数量,用逗号隔开.)", FCVAR_NONE);

    g_cvDebug = CreateConVar("sm_saferoom_weapons_debug", "0", "调试开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_connect_full", Event_PlayerConnectFull, EventHookMode_Post);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    //HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
    //HookEvent("mission_lost", Event_Mission_Lost, EventHookMode_PostNoCopy);

    g_aWeapons = new ArrayList(ByteCountToCells(64));
    g_aCounts = new ArrayList();
    
    g_WeaponNameToId = new StringMap();
    InitializeWeaponNameToIdMap();
    
    //预加载武器模型,这个不需要了,用下面的
    //PrecacheWeaponModels();
    
    //l4d2util_weapons.inc里的预缓存
    L4D2Weapons_Init();
}

/*
* player_connect_full 事件让玩家载入后才生成武器
* 避免无人还搁哪无限循环,
* 之后重开才需要轮到 round_start 事件
* 因此round_start事件只会在 g_bWeaponsSpawned = false 的时候才执行
* 即玩家未载入游戏时不执行 round_start 事件,
* 必须确保 player_connect_full 和 round_start 只能执行其中一个
*/

//玩家完全载入后0.2秒才执行
//玩家首次进入服务器,换图后进入重新回到服务器等都会执行这个事件
public void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
    /*
    if (g_bWeaponsSpawned)  //如果为true,先改为false
    {
        g_bWeaponsSpawned = false;
    }
    */

    //玩家已载入游戏(true)，直接返回
    if (g_bPlayerConnected)
    {
        return;
    }

    g_bPlayerConnected = true;

    g_aWeapons.Clear();
    g_aCounts.Clear();

    UpdateConVars();
    CreateTimer(0.2, Timer_SpawnWeapons, _, TIMER_FLAG_NO_MAPCHANGE);

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("Event_PlayerConnectFull执行!");
    }
}

//确保不能和Event_PlayerConnectFull重复执行
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    //武器已生成(teue),直接返回
    if (g_bWeaponsSpawned)
    {
        return;
    }

    //玩家未载入游戏(false)，直接返回
    if (!g_bPlayerConnected)
    {
        return;
    }

    g_aWeapons.Clear();
    g_aCounts.Clear();

    UpdateConVars();
    CreateTimer(0.2, Timer_SpawnWeapons, _, TIMER_FLAG_NO_MAPCHANGE);

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("Event_RoundStart执行!");
    }
}

//对抗回合结束,或者战役团灭
//注意,zm药抗里roundend会被连续执行两次
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{

    //如果已执行过一次(true),则返回
    if (g_bRoundEndExecuted)
    {
        return;
    }

    g_bRoundEndExecuted = true;

    g_bWeaponsSpawned = false;
    g_bPlayerConnected = true;
    g_aWeapons.Clear();
    g_aCounts.Clear();

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("Event_RoundEnd执行! 成功标记为已执行!");
    }
}

/*
//自然过渡地图
public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    g_bWeaponsSpawned = false;
    g_bPlayerConnected = false;
    g_aWeapons.Clear();
    g_aCounts.Clear();

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("Event_MapTransition执行!");
    }
}

//战役团灭
public void Event_Mission_Lost(Event event, const char[] name, bool dontBroadcast)
{
    g_bWeaponsSpawned = false;
    g_bPlayerConnected = true;
    g_aWeapons.Clear();
    g_aCounts.Clear();

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("Event_Mission_Lost执行!");
    }
}
*/

//地图切换,包含了过渡
public void OnMapEnd()
{
    g_bRoundEndExecuted = false;
    g_bWeaponsSpawned = false;
    g_bPlayerConnected = false;
    g_aWeapons.Clear();
    g_aCounts.Clear();

    if (g_cvDebug.BoolValue)
    {
        PrintToServer("OnMapEnd执行!");
    }
}

//武器名称-id映射
void InitializeWeaponNameToIdMap()
{
    g_WeaponNameToId.SetValue("pistol", WEPID_PISTOL);
    g_WeaponNameToId.SetValue("smg", WEPID_SMG);
    g_WeaponNameToId.SetValue("pumpshotgun", WEPID_PUMPSHOTGUN);
    g_WeaponNameToId.SetValue("autoshotgun", WEPID_AUTOSHOTGUN);
    g_WeaponNameToId.SetValue("rifle", WEPID_RIFLE);
    g_WeaponNameToId.SetValue("hunting_rifle", WEPID_HUNTING_RIFLE);
    g_WeaponNameToId.SetValue("smg_silenced", WEPID_SMG_SILENCED);
    g_WeaponNameToId.SetValue("shotgun_chrome", WEPID_SHOTGUN_CHROME);
    g_WeaponNameToId.SetValue("rifle_desert", WEPID_RIFLE_DESERT);
    g_WeaponNameToId.SetValue("sniper_military", WEPID_SNIPER_MILITARY);
    g_WeaponNameToId.SetValue("shotgun_spas", WEPID_SHOTGUN_SPAS);
    g_WeaponNameToId.SetValue("grenade_launcher", WEPID_GRENADE_LAUNCHER);
    g_WeaponNameToId.SetValue("rifle_ak47", WEPID_RIFLE_AK47);
    g_WeaponNameToId.SetValue("pistol_magnum", WEPID_PISTOL_MAGNUM);
    g_WeaponNameToId.SetValue("smg_mp5", WEPID_SMG_MP5);
    g_WeaponNameToId.SetValue("rifle_sg552", WEPID_RIFLE_SG552);
    g_WeaponNameToId.SetValue("sniper_awp", WEPID_SNIPER_AWP);
    g_WeaponNameToId.SetValue("sniper_scout", WEPID_SNIPER_SCOUT);
    g_WeaponNameToId.SetValue("rifle_m60", WEPID_RIFLE_M60);
}

/*
// 预加载枪械模型,不需要了
void PrecacheWeaponModels()
{
    PrecacheModel("models/w_models/weapons/w_pistol_b.mdl", true);
    PrecacheModel("models/w_models/weapons/w_desert_eagle.mdl", true);
    PrecacheModel("models/w_models/weapons/w_smg_uzi.mdl", true);
    PrecacheModel("models/w_models/weapons/w_smg_a.mdl", true);
    PrecacheModel("models/w_models/weapons/w_smg_mp5.mdl", true);
    PrecacheModel("models/w_models/weapons/w_rifle_m16a2.mdl", true);
    PrecacheModel("models/w_models/weapons/w_rifle_ak47.mdl", true);
    PrecacheModel("models/w_models/weapons/w_rifle_sg552.mdl", true);
    PrecacheModel("models/w_models/weapons/w_sniper_scout.mdl", true);
    PrecacheModel("models/w_models/weapons/w_sniper_military.mdl", true);
    PrecacheModel("models/w_models/weapons/w_sniper_awp.mdl", true);
    PrecacheModel("models/w_models/weapons/w_sniper_mini14.mdl", true);
    PrecacheModel("models/w_models/weapons/w_rifle_b.mdl", true);
    PrecacheModel("models/w_models/weapons/w_shotgun_spas.mdl", true);
    PrecacheModel("models/w_models/weapons/w_pumpshotgun.mdl", true);
    PrecacheModel("models/w_models/weapons/w_pumpshotgun_a.mdl", true);
    PrecacheModel("models/w_models/weapons/w_autoshot_m4super.mdl", true);
    PrecacheModel("models/w_models/weapons/w_grenade_launcher.mdl", true);
    PrecacheModel("models/w_models/weapons/w_m60.mdl", true);
}
*/

void UpdateConVars()
{
    g_bEnabled = g_cvEnable.BoolValue;
    
    //解析武器列表的设置,逗号分隔
    char sWeapons[256];
    g_cvWeapons.GetString(sWeapons, sizeof(sWeapons));
    
    char weaponBuffer[64][64];
    int weaponCount = ExplodeString(sWeapons, ",", weaponBuffer, sizeof(weaponBuffer), sizeof(weaponBuffer[]));
    
    for (int i = 0; i < weaponCount; i++)
    {
        TrimString(weaponBuffer[i]);
        if (strlen(weaponBuffer[i]) > 0)
        {
            g_aWeapons.PushString(weaponBuffer[i]);
        }
    }
    
    //解析数量列表的设置
    char sCounts[256];
    g_cvCounts.GetString(sCounts, sizeof(sCounts));
    
    char countBuffer[64][16];
    int countCount = ExplodeString(sCounts, ",", countBuffer, sizeof(countBuffer), sizeof(countBuffer[]));
    
    for (int i = 0; i < countCount; i++)
    {
        TrimString(countBuffer[i]);
        if (strlen(countBuffer[i]) > 0)
        {
            g_aCounts.Push(StringToInt(countBuffer[i]));
        }
    }
    
    //确保武器和数量数组的长度一致，否则默认设置为1
    int weaponsCount = g_aWeapons.Length;
    int countsCount = g_aCounts.Length;
    
    if (countsCount < weaponsCount)
    {
        for (int i = countsCount; i < weaponsCount; i++)
        {
            g_aCounts.Push(1);
        }
    }
    else if (countsCount > weaponsCount)
    {
        for (int i = weaponsCount; i < countsCount; i++)
        {
            g_aCounts.Erase(weaponsCount);
        }
    }
}

//计时器回调
/*
//起点和终点安全屋，使用l4d2lib里的
//有些三方图用这个不靠谱
//甚至有的神经三方图把起点屋子和终点屋子颠倒的
public Action Timer_SpawnWeapons(Handle timer)
{
    if (!g_bEnabled || g_bWeaponsSpawned)
    {
        return Plugin_Stop;
    }
    
    float startSaferoomOrigin[3];
    L4D2_GetMapStartOrigin(startSaferoomOrigin);    //起点屋子
    SpawnWeaponsAtLocation(startSaferoomOrigin);
    
    float endSaferoomOrigin[3];
    L4D2_GetMapEndOrigin(endSaferoomOrigin);        //终点屋子
    SpawnWeaponsAtLocation(endSaferoomOrigin);
    
    //标记为true，表示已生成
    g_bWeaponsSpawned = true;
    return Plugin_Stop;
}
*/

//模仿meleeinthesaferoom插件的无脑重试循环机制
//但仅限有玩家进入才执行
public Action Timer_SpawnWeapons(Handle timer)
{
    if (!g_bEnabled || g_bWeaponsSpawned)
    {
        return Plugin_Stop;
    }
    
    // 获取第一个在游戏中的生还者客户端坐标
    float survivorOrigin[3];
    if (GetFirstSurvivorOrigin(survivorOrigin))
    {
        SpawnWeaponsAtLocation(survivorOrigin);
        //标记为true，表示已生成
        g_bWeaponsSpawned = true;

        if (g_cvDebug.BoolValue)
        {
            PrintToServer("枪械成功生成了捏~~");
        }

        return Plugin_Stop;
    }
    else
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("无法找到生还,3秒后重试...");
        }

        // 3秒后重试
        CreateTimer(3.0, Timer_SpawnWeapons, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
}

//获取第一个在游戏内u的生还坐标
bool GetFirstSurvivorOrigin(float origin[3])
{
    //遍历所有客户端,找到第一个在游戏中的生还
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            GetClientAbsOrigin(i, origin);  //坐标获取
            return true;
        }
    }
    
    return false;
}

//武器位置偏移
void SpawnWeaponsAtLocation(float saferoomOrigin[3])
{
    for (int i = 0; i < g_aWeapons.Length; i++)
    {
        char weaponName[64];
        g_aWeapons.GetString(i, weaponName, sizeof(weaponName));
        
        int count = g_aCounts.Get(i);
        
        for (int j = 0; j < count; j++)
        {
            float spawnPos[3];
            //偏移量
            spawnPos[0] = saferoomOrigin[0] + GetRandomFloat(-10.0, 10.0);
            spawnPos[1] = saferoomOrigin[1] + GetRandomFloat(-10.0, 10.0);
            spawnPos[2] = saferoomOrigin[2] + 5.0;  //向上一点点
            
            SpawnWeapon(weaponName, spawnPos);
        }
    }
}

//武器实体生成逻辑
void SpawnWeapon(const char[] weaponName, float position[3])
{
    int weaponId;
    if (!g_WeaponNameToId.GetValue(weaponName, weaponId))
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("未知的武器名称: %s", weaponName);
        }

        return;
    }
    
    char entityName[64];
    if (StrEqual(weaponName, "smg"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_smg");
    }
    else if (StrEqual(weaponName, "smg_silenced"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_smg_silenced");
    }
    else if (StrEqual(weaponName, "rifle"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_rifle");
    }
    else if (StrEqual(weaponName, "rifle_ak47"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_rifle_ak47");
    }
    else if (StrEqual(weaponName, "pistol"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_pistol");
    }
    else if (StrEqual(weaponName, "pumpshotgun"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_pumpshotgun");
    }
    else if (StrEqual(weaponName, "autoshotgun"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_autoshotgun");
    }
    else if (StrEqual(weaponName, "hunting_rifle"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_hunting_rifle");
    }
    else if (StrEqual(weaponName, "shotgun_chrome"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_shotgun_chrome");
    }
    else if (StrEqual(weaponName, "rifle_desert"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_rifle_desert");
    }
    else if (StrEqual(weaponName, "sniper_military"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_sniper_military");
    }
    else if (StrEqual(weaponName, "shotgun_spas"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_shotgun_spas");
    }
    else if (StrEqual(weaponName, "grenade_launcher"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_grenade_launcher");
    }
    else if (StrEqual(weaponName, "pistol_magnum"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_pistol_magnum");
    }
    else if (StrEqual(weaponName, "smg_mp5"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_smg_mp5");
    }
    else if (StrEqual(weaponName, "rifle_sg552"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_rifle_sg552");
    }
    else if (StrEqual(weaponName, "sniper_awp"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_sniper_awp");
    }
    else if (StrEqual(weaponName, "sniper_scout"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_sniper_scout");
    }
    else if (StrEqual(weaponName, "rifle_m60"))
    {
        strcopy(entityName, sizeof(entityName), "weapon_rifle_m60");
    }
    else
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("未知的武器名称,无法创建实体: %s", weaponName);
        }

        return;
    }
    
    int weapon = CreateEntityByName(entityName);
    if (weapon == -1)
    {
        if (g_cvDebug.BoolValue)
        {
            PrintToServer("无法创建武器实体: %s", entityName);
        }

        return;
    }
    
    /*
    //用上面那个就行了
    char modelName[PLATFORM_MAX_PATH];
    if (StrEqual(weaponName, "smg"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_smg_uzi.mdl");
    }
    else if (StrEqual(weaponName, "smg_silenced"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_smg_a.mdl");
    }
    else if (StrEqual(weaponName, "rifle"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_rifle_m16a2.mdl");
    }
    else if (StrEqual(weaponName, "rifle_ak47"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_rifle_ak47.mdl");
    }
    else if (StrEqual(weaponName, "pistol"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_pistol_b.mdl");
    }
    else if (StrEqual(weaponName, "pumpshotgun"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_pumpshotgun.mdl");
    }
    else if (StrEqual(weaponName, "autoshotgun"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_autoshot_m4super.mdl");
    }
    else if (StrEqual(weaponName, "hunting_rifle"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_sniper_mini14.mdl");
    }
    else if (StrEqual(weaponName, "shotgun_chrome"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_pumpshotgun_a.mdl");
    }
    else if (StrEqual(weaponName, "rifle_desert"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_rifle_b.mdl");
    }
    else if (StrEqual(weaponName, "sniper_military"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_sniper_military.mdl");
    }
    else if (StrEqual(weaponName, "shotgun_spas"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_shotgun_spas.mdl");
    }
    else if (StrEqual(weaponName, "grenade_launcher"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_grenade_launcher.mdl");
    }
    else if (StrEqual(weaponName, "pistol_magnum"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_desert_eagle.mdl");
    }
    else if (StrEqual(weaponName, "smg_mp5"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_smg_mp5.mdl");
    }
    else if (StrEqual(weaponName, "rifle_sg552"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_rifle_sg552.mdl");
    }
    else if (StrEqual(weaponName, "sniper_awp"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_sniper_awp.mdl");
    }
    else if (StrEqual(weaponName, "sniper_scout"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_sniper_scout.mdl");
    }
    else if (StrEqual(weaponName, "rifle_m60"))
    {
        strcopy(modelName, sizeof(modelName), "models/w_models/weapons/w_m60.mdl");
    }
    */
    //SetEntityModel(weapon, modelName);

    DispatchSpawn(weapon);
    ActivateEntity(weapon);

    SetWeaponAmmo(weapon, weaponName);
    
    float angles[3] = {0.0, 0.0, 0.0};      //表示方向，无所谓的
    TeleportEntity(weapon, position, angles, NULL_VECTOR);
}

//备弹，如果不设置就变成没有了，干脆设置成默认
void SetWeaponAmmo(int weapon, const char[] weaponName)
{
    //只为主武器设置备弹
    if (StrEqual(weaponName, "smg") || StrEqual(weaponName, "smg_silenced") || StrEqual(weaponName, "smg_mp5"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 650);
    }
    else if (StrEqual(weaponName, "rifle") || StrEqual(weaponName, "rifle_ak47") || 
             StrEqual(weaponName, "rifle_desert") || StrEqual(weaponName, "rifle_sg552"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 360);
    }
    else if (StrEqual(weaponName, "autoshotgun") || StrEqual(weaponName, "shotgun_spas"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 90);
    }
    else if (StrEqual(weaponName, "pumpshotgun") || StrEqual(weaponName, "shotgun_chrome"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 72);
    }
    else if (StrEqual(weaponName, "hunting_rifle"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 150);
    }
    else if (StrEqual(weaponName, "sniper_military") || StrEqual(weaponName, "sniper_awp") || StrEqual(weaponName, "sniper_scout"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 180);
    }
    else if (StrEqual(weaponName, "grenade_launcher"))
    {
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 30);
    }
    else if (StrEqual(weaponName, "pistol") || StrEqual(weaponName, "pistol_magnum") || StrEqual(weaponName, "rifle_m60"))
    {
        //这几个特殊的不设置任何值
        return;
    }
    else
    {
        //未知类型随便设置个
        SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", 72);
    }
}
