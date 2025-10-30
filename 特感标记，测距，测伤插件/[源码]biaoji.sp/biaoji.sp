#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <left4dhooks>

Handle
    g_hCookie,
    g_hDamageTimer[MAXPLAYERS + 1];

float
    g_fPoint1[MAXPLAYERS + 1][3],
    g_fPoint2[MAXPLAYERS + 1][3],
    g_fDamageCache[MAXPLAYERS + 1][MAXPLAYERS + 1];

bool
    g_bPluginEnabled,
    g_bPluginDmg,
    g_bPluginSIHighLight,
    g_bPoint1Set[MAXPLAYERS + 1],
    g_bPoint2Set[MAXPLAYERS + 1],
    g_bDamageActive[MAXPLAYERS + 1];

int
    g_iWitchModel1[MAXPLAYERS + 1],
    g_iWitchModel2[MAXPLAYERS + 1];

ConVar
    g_cvPluginEnabled,
    g_cvPluginDmg,
    g_cvPluginSIHighLight;

ArrayList
    g_aSpawnedSI[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "星云猫猫标记测距",
    author = "Seiunsky Maomao",
    description = "自用的测距插件, 功能是标记脚下两点坐标, 并计算距离, 以及特感的冻结、生成功能.",
    version = "1.4",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    //插件开关
    g_cvPluginEnabled = CreateConVar("bjkg", "1", "插件开关 [1 → 开启 | 0 → 关闭]", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvPluginDmg = CreateConVar("bj_dmg", "0", "显示造成的伤害 [1 → 显示 | 0 → 不显示]", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvPluginSIHighLight = CreateConVar("bj_sihl", "0", "显示特感高亮光圈 [1 → 显示 | 0 → 不显示]", FCVAR_NONE, true, 0.0, true, 1.0);

    //管理员命令
    RegAdminCmd("sm_biaoji1", Command_MarkPoint1, ADMFLAG_GENERIC, "标记、取消坐标点1");
    RegAdminCmd("sm_biaoji2", Command_MarkPoint2, ADMFLAG_GENERIC, "标记、取消坐标点2");
    RegAdminCmd("sm_biaoji", Command_ToggleMenu, ADMFLAG_GENERIC, "打开坐标传送栏");
    RegAdminCmd("sm_si", Command_SpawnSI, ADMFLAG_GENERIC, "打开特感生成表");

    //注册插件开关的ConVar
    g_bPluginEnabled = GetConVarBool(g_cvPluginEnabled);
    g_bPluginDmg = GetConVarBool(g_cvPluginDmg);
    g_bPluginSIHighLight = GetConVarBool(g_cvPluginSIHighLight);

    //注册客户端cookie,用于存储标记点
    g_hCookie = RegClientCookie("biaoji_points", "存储标记点", CookieAccess_Private);

    //监听ConVar变化
    HookConVarChange(g_cvPluginEnabled, OnConVarChanged);
    HookConVarChange(g_cvPluginDmg, OnConVarChanged);
    HookConVarChange(g_cvPluginSIHighLight, OnConVarChanged);

    //检查客户端cookie是否已缓存
    for (int i = 1; i <= MaxClients; i++)
    {
        if (AreClientCookiesCached(i))
        {
            OnClientCookiesCached(i);
        }
    }

    //初始化特殊感染者存储数组
    for (int i = 1; i <= MaxClients; i++)
    {
        g_aSpawnedSI[i] = new ArrayList();
    }
}

//ConVar变化回调
public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvPluginEnabled)
    {
        g_bPluginEnabled = GetConVarBool(g_cvPluginEnabled);
    }
    if (convar == g_cvPluginDmg)
    {
        g_bPluginDmg = GetConVarBool(g_cvPluginDmg);
    }
    if (convar == g_cvPluginSIHighLight)
    {
        g_bPluginSIHighLight = GetConVarBool(g_cvPluginSIHighLight);
    }
}

//需要预加载模型
public void OnMapStart()
{
    PrecacheModel("models/infected/witch_bride.mdl");   //用新娘妹子来代替
}

//读取标记点
public void OnClientCookiesCached(int client)
{
    if (!g_bPluginEnabled)
    {
        return;
    }

    //读取客户端 Cookie 中的标记点数据
    char sCookieValue[256];
    GetClientCookie(client, g_hCookie, sCookieValue, sizeof(sCookieValue));

    if (strlen(sCookieValue) > 0)
    {
        char sPoints[2][64];
        ExplodeString(sCookieValue, "|", sPoints, 2, 64);

        if (StrContains(sPoints[0], ",") != -1)
        {
            StringToVector(sPoints[0], g_fPoint1[client]);
            g_bPoint1Set[client] = true;
            CreateWitchModel(client, 1); // 创建第一个点
        }

        if (StrContains(sPoints[1], ",") != -1)
        {
            StringToVector(sPoints[1], g_fPoint2[client]);
            g_bPoint2Set[client] = true;
            CreateWitchModel(client, 2); // 创建第二个点
        }
    }
}

//标记点1
public Action Command_MarkPoint1(int client, int args)
{
    if (!g_bPluginEnabled)
    {
        ReplyToCommand(client, "插件功能已关闭.");
        return Plugin_Handled;
    }

    if (g_bPoint1Set[client])
    {
        //取消第一个点
        g_bPoint1Set[client] = false;
        PrintToChat(client, "取消坐标点1.");
        RemoveWitchModel(client, 1); // 移除第一个点
    }
    else
    {
        //标记第一个点
        GetClientAbsOrigin(client, g_fPoint1[client]);
        g_bPoint1Set[client] = true;
        
        //点1流程距离
        float flowDistance1 = GetFlowFromPoint(g_fPoint1[client]);
        
        PrintToChat(client, "坐标点1: (%.2f, %.2f, %.2f)", g_fPoint1[client][0], g_fPoint1[client][1], g_fPoint1[client][2]);
        PrintToChat(client, "坐标点1流程: %.2f", flowDistance1);
        CreateWitchModel(client, 1); // 创建第一个点

        //如果两个点都已标记，计算距离和流程间距
        if (g_bPoint1Set[client] && g_bPoint2Set[client])
        {
            float distance = CalculateDistance(g_fPoint1[client], g_fPoint2[client]);
            float flowDistance2 = GetFlowFromPoint(g_fPoint2[client]);
            float flowDistanceDiff = FloatAbs(flowDistance1 - flowDistance2);
            
            PrintToChat(client, "两点间直线距离: %.2f", distance);
            PrintToChat(client, "两点间流程间距: %.2f", flowDistanceDiff);
        }
    }

    SavePoints(client); //保存标记点
    return Plugin_Handled;
}

//标记点2
public Action Command_MarkPoint2(int client, int args)
{
    if (!g_bPluginEnabled)
    {
        ReplyToCommand(client, "插件功能已关闭。");
        return Plugin_Handled;
    }

    if (g_bPoint2Set[client])
    {
        // 取消第二个点
        g_bPoint2Set[client] = false;
        PrintToChat(client, "取消坐标点2.");
        RemoveWitchModel(client, 2); //移除第二个点
    }
    else
    {
        // 标记第二个点
        GetClientAbsOrigin(client, g_fPoint2[client]);
        g_bPoint2Set[client] = true;
        
        //点2流程距离
        float flowDistance2 = GetFlowFromPoint(g_fPoint2[client]);
        
        PrintToChat(client, "坐标点2: (%.2f, %.2f, %.2f)", g_fPoint2[client][0], g_fPoint2[client][1], g_fPoint2[client][2]);
        PrintToChat(client, "坐标点2流程: %.2f", flowDistance2);
        CreateWitchModel(client, 2);    //创建第二个点

        // 如果两个点都已标记，计算距离和流程间距
        if (g_bPoint1Set[client] && g_bPoint2Set[client])
        {
            float distance = CalculateDistance(g_fPoint1[client], g_fPoint2[client]);
            float flowDistance1 = GetFlowFromPoint(g_fPoint1[client]);
            float flowDistanceDiff = FloatAbs(flowDistance1 - flowDistance2);
            
            PrintToChat(client, "两点间直线距离: %.2f", distance);
            PrintToChat(client, "两点间流程间距: %.2f", flowDistanceDiff);
        }
    }

    SavePoints(client); //保存点
    return Plugin_Handled;
}

//左侧栏菜单命令
public Action Command_ToggleMenu(int client, int args)
{
    if (!g_bPluginEnabled)
    {
        ReplyToCommand(client, "插件功能已关闭。");
        return Plugin_Handled;
    }

    ShowPointsMenu(client);
    return Plugin_Handled;
}

//左侧栏菜单
void ShowPointsMenu(int client)
{
    if (!g_bPluginEnabled)
    {
        PrintToChat(client, "插件功能已关闭.");
        return;
    }

    Menu menu = new Menu(PointsMenuHandler);
    menu.SetTitle("坐标点菜单");

    if (g_bPoint1Set[client])
    {
        menu.AddItem("point1", "传送到坐标点1");
    }

    if (g_bPoint2Set[client])
    {
        menu.AddItem("point2", "传送到坐标点2");
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

//传送
public int PointsMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        if (StrEqual(sInfo, "point1"))
        {
            TeleportEntity(client, g_fPoint1[client], NULL_VECTOR, NULL_VECTOR); // 传送到点1
        }
        else if (StrEqual(sInfo, "point2"))
        {
            TeleportEntity(client, g_fPoint2[client], NULL_VECTOR, NULL_VECTOR); // 传送到点2
        }

        // 重新显示菜单，保持左侧栏打开
        ShowPointsMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu; // 删除菜单
    }

    return 0; // 函数必须返回一个值
}

//保存坐标
void SavePoints(int client)
{
    if (!g_bPluginEnabled)
    {
        return;
    }

    char sCookieValue[256];
    Format(sCookieValue, sizeof(sCookieValue), "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f", 
        g_fPoint1[client][0], g_fPoint1[client][1], g_fPoint1[client][2],
        g_fPoint2[client][0], g_fPoint2[client][1], g_fPoint2[client][2]);

    SetClientCookie(client, g_hCookie, sCookieValue); // 保存点到客户端cookie
}

//坐标位置
void StringToVector(const char[] sString, float fVector[3])
{
    char sParts[3][16];
    ExplodeString(sString, ",", sParts, 3, 16);

    fVector[0] = StringToFloat(sParts[0]);
    fVector[1] = StringToFloat(sParts[1]);
    fVector[2] = StringToFloat(sParts[2]);
}

//模型
void CreateWitchModel(int client, int point)
{
    float vPos[3];
    float vAng[3]; // 存储旋转角度用的
    int entity;

    if (point == 1)
    {
        vPos = g_fPoint1[client];
        entity = CreateEntityByName("prop_dynamic_override");
    }
    else if (point == 2)
    {
        vPos = g_fPoint2[client];
        entity = CreateEntityByName("prop_dynamic_override");
    }

    if (entity == -1) return;

    // 设置模型
    DispatchKeyValue(entity, "model", "models/infected/witch_bride.mdl");
    DispatchKeyValue(entity, "disableshadows", "1"); // 禁用阴影
    DispatchKeyValue(entity, "solid", "0"); // 取消碰撞
    DispatchSpawn(entity);

    // 设置发光轮廓
    SetEntProp(entity, Prop_Send, "m_nGlowRange", 9999); // 发光范围
    SetEntProp(entity, Prop_Send, "m_iGlowType", 3); // 发光类型
    SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0x00FF00); // 绿色
    AcceptEntityInput(entity, "StartGlowing");

    // 设置模型位置和旋转角度
    vAng[0] = 270.0; // X轴
    vAng[1] = 0.0; // Y轴
    vAng[2] = 0.0; // Z轴
    TeleportEntity(entity, vPos, vAng, NULL_VECTOR);

    // 存储模型实体索引
    if (point == 1)
    {
        g_iWitchModel1[client] = EntIndexToEntRef(entity);
    }
    else if (point == 2)
    {
        g_iWitchModel2[client] = EntIndexToEntRef(entity);
    }
}

//移除模型
void RemoveWitchModel(int client, int point)
{
    int entity;

    if (point == 1)
    {
        entity = EntRefToEntIndex(g_iWitchModel1[client]);
        g_iWitchModel1[client] = -1;
    }
    else if (point == 2)
    {
        entity = EntRefToEntIndex(g_iWitchModel2[client]);
        g_iWitchModel2[client] = -1;
    }

    if (entity != -1 && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Kill"); // 移除模型
    }
}

// 计算两点间的距离
float CalculateDistance(float point1[3], float point2[3])
{
    float dx = point1[0] - point2[0];
    float dy = point1[1] - point2[1];
    float dz = point1[2] - point2[2];
    return SquareRoot(dx * dx + dy * dy + dz * dz); //勾股定理是好东西
}

// 特感创建事件
public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_bPluginEnabled)
    {
        return;
    }

    if (StrEqual(classname, "smoker") || StrEqual(classname, "hunter") || StrEqual(classname, "boomer") || StrEqual(classname, "spitter") || StrEqual(classname, "jockey") || StrEqual(classname, "charger") || StrEqual(classname, "tank") || StrEqual(classname, "tank_rock") || StrEqual(classname, "witch"))
    {
        if (g_bPluginDmg)
        {
            SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_SI);
        }
        
        if (g_bPluginSIHighLight)
        {
            SetEntProp(entity, Prop_Send, "m_nGlowRange", 9999);
            SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
            SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0xFFC0CB);
        }
    }
}

//显示和计算攻击的伤害值
public Action OnTakeDamage_SI(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_bPluginDmg || !g_bPluginEnabled)
    {
        return Plugin_Continue;
    }

    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        // 实时显示每一枪/每一颗弹丸的伤害
        PrintToChat(attacker, "\x01[!] \x03对目标造成 \x04%.2f点 \x03伤害.", damage);

        // 延迟显示 2.0 秒内的总伤害值
        if (g_bDamageActive[attacker])
        {
            // 如果攻击者已经在累积伤害，则将伤害值累加
            g_fDamageCache[attacker][victim] += damage;
            // 重置计时器
            KillTimer(g_hDamageTimer[attacker]);
            g_hDamageTimer[attacker] = CreateTimer(2.0, Timer_DisplayTotalDamage, attacker);
        }
        else
        {
            // 如果攻击者没有在累积伤害，则初始化伤害缓存并启动计时器
            for (int i = 1; i <= MaxClients; i++)
            {
                g_fDamageCache[attacker][i] = 0.0; // 清空缓存
            }
            g_fDamageCache[attacker][victim] = damage; // 记录当前伤害
            g_bDamageActive[attacker] = true; // 标记为正在累积伤害
            g_hDamageTimer[attacker] = CreateTimer(1.5, Timer_DisplayTotalDamage, attacker); // 启动计时器
        }
    }

    return Plugin_Continue;
}

//总伤计时回调
public Action Timer_DisplayTotalDamage(Handle timer, any attacker)
{
    g_bDamageActive[attacker] = false; // 标记为不再累积伤害

    if (!IsClientInGame(attacker)) return Plugin_Stop; // 如果攻击者不在游戏中，停止计时器

    // 遍历所有玩家，显示总伤害值
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && g_fDamageCache[attacker][i] > 0.0)
        {
            // 显示总伤害值
            PrintToChat(attacker, "\x01[总伤] \x03对目标造成的总伤害 \x04%.2f点 \x03.", g_fDamageCache[attacker][i]);

            // 清空伤害缓存
            g_fDamageCache[attacker][i] = 0.0;
        }
    }

    return Plugin_Stop; // 停止计时器
}

// 特感生成菜单命令
public Action Command_SpawnSI(int client, int args)
{
    if (!g_bPluginEnabled)
    {
        ReplyToCommand(client, "插件功能已关闭.");
        ReplyToCommand(client, "请使用 !sm_cvar bjkg 1 打开插件开关.");
        return Plugin_Handled;
    }

    ShowSpawnSIMenu(client); // 显示特殊感染者生成菜单
    return Plugin_Handled;
}

// 显示特殊感染者生成菜单
void ShowSpawnSIMenu(int client)
{
    Menu menu = new Menu(SpawnSIMenuHandler);
    menu.SetTitle("功能菜单:");

    MoveType movetype = GetEntityMoveType(client);
    if (movetype != MOVETYPE_NOCLIP)
    {
        menu.AddItem("noclip", "开启穿墙");
    }
    else
    {
        menu.AddItem("noclip", "关闭穿墙");
    }

    //伤害显示开关
    char dmgDisplay[32];
    Format(dmgDisplay, sizeof(dmgDisplay), "伤害显示:%s", g_bPluginDmg ? "开启" : "关闭");
    menu.AddItem("dmg_toggle", dmgDisplay);

    //特感高亮开关
    char siHighlight[32];
    Format(siHighlight, sizeof(siHighlight), "特感高亮:%s", g_bPluginSIHighLight ? "开启" : "关闭");
    menu.AddItem("sihl_toggle", siHighlight);

    //重做冻结开关
    char freezeDisplay[32];
    ConVar freezeCvar = FindConVar("nb_blind");
    int freezeState = (freezeCvar != null) ? GetConVarInt(freezeCvar) : 0;
    Format(freezeDisplay, sizeof(freezeDisplay), "特感冻结:%s", freezeState == 0 ? "关闭" : "开启");
    menu.AddItem("freeze", freezeDisplay);

    menu.AddItem("smoker", "生成舌头");
    menu.AddItem("boomer", "生成胖子");
    menu.AddItem("hunter", "生成猎人");
    menu.AddItem("spitter", "生成口水");
    menu.AddItem("jockey", "生成猴子");
    menu.AddItem("charger", "生成牛牛");
    menu.AddItem("tank", "生成坦克");

    menu.Display(client, MENU_TIME_FOREVER);
}

//菜单功能回调处理
public int SpawnSIMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        //处理穿墙
        if (StrEqual(sInfo, "noclip"))
        {
            MoveType movetype = GetEntityMoveType(client);
            if (movetype != MOVETYPE_NOCLIP)
            {
                SetEntityMoveType(client, MOVETYPE_NOCLIP);
                PrintToChat(client, "\x04穿墙已\x05开启\x04.");
            }
            else
            {
                SetEntityMoveType(client, MOVETYPE_WALK);
                PrintToChat(client, "\x04穿墙已\x05关闭\x04.");
            }

            // 重新显示菜单
            ShowSpawnSIMenu(client);
            return 0;
        }

        //处理伤害显示开关回调
        if (StrEqual(sInfo, "dmg_toggle"))
        {
            // 切换伤害显示状态
            bool newState = !g_bPluginDmg;
            SetConVarBool(g_cvPluginDmg, newState);
            PrintToChat(client, "\x04伤害显示已\x05%s\x04.", newState ? "开启" : "关闭");
            
            // 重新显示菜单
            ShowSpawnSIMenu(client);
            return 0;
        }

        //处理特感高亮开关回调
        if (StrEqual(sInfo, "sihl_toggle"))
        {
            // 切换特感高亮状态
            bool newState = !g_bPluginSIHighLight;
            SetConVarBool(g_cvPluginSIHighLight, newState);
            PrintToChat(client, "\x04特感高亮已\x05%s\x04.", newState ? "开启" : "关闭");
            
            // 重新显示菜单
            ShowSpawnSIMenu(client);
            return 0;
        }

        //不再用sm_cvar nb_blind来处理
        //换更好的
        if (StrEqual(sInfo, "freeze"))
        {
            // 获取当前的冻结状态
            ConVar freezeCvar = FindConVar("nb_blind");
            if (freezeCvar != null)
            {
                int currentState = GetConVarInt(freezeCvar);
                if (currentState == 0)
                {
                    SetConVarInt(freezeCvar, 1);
                    PrintToChat(client, "\x04特感冻结已\x05开启\x04.");
                }
                else
                {
                    SetConVarInt(freezeCvar, 0);
                    PrintToChat(client, "\x04特感冻结已\x05关闭\x04.");
                }
            }

            // 重新显示菜单
            ShowSpawnSIMenu(client);
            return 0;
        }

        // 获取玩家准心位置
        float vPos[3];
        GetClientEyePosition(client, vPos);
        float vAng[3];
        GetClientEyeAngles(client, vAng);
        TR_TraceRayFilter(vPos, vAng, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
        TR_GetEndPosition(vPos);

        // 生成特殊感染者
        char siType[32];
        if (StrEqual(sInfo, "smoker"))
        {
            siType = "smoker";
        }
        else if (StrEqual(sInfo, "boomer"))
        {
            siType = "boomer";
        }
        else if (StrEqual(sInfo, "hunter"))
        {
            siType = "hunter";
        }
        else if (StrEqual(sInfo, "spitter"))
        {
            siType = "spitter";
        }
        else if (StrEqual(sInfo, "jockey"))
        {
            siType = "jockey";
        }
        else if (StrEqual(sInfo, "charger"))
        {
            siType = "charger";
        }
        else if (StrEqual(sInfo, "tank"))
        {
            siType = "tank";
        }

        // 模仿的all4dead2.sp, 直接抄来使用StripAndExecuteClientCommand执行z_spawn命令
        StripAndExecuteClientCommand(client, "z_spawn", siType);

        // 重新显示菜单
        ShowSpawnSIMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu; // 删除菜单
    }

    return 0;
}

// 射线过滤, 防止射线击中玩家身上
public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
    return entity != data;
}

// 抄all4dead2的, 主要是为了执行z_spawn命令
void StripAndExecuteClientCommand(int client, const char[] command, const char[] arguments)
{
    // 获取命令的标志
    int flags = GetCommandFlags(command);
    // 移除作弊保护标志
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    // 执行命令
    FakeClientCommand(client, "%s %s", command, arguments);
    // 恢复命令的标志
    SetCommandFlags(command, flags);
}

//断开连接清除
public void OnClientDisconnect(int client)
{
    // 清除第一个点的标记和模型
    if (g_bPoint1Set[client])
    {
        g_bPoint1Set[client] = false;
        RemoveWitchModel(client, 1);
    }

    // 清除第二个点的标记和模型
    if (g_bPoint2Set[client])
    {
        g_bPoint2Set[client] = false;
        RemoveWitchModel(client, 2);
    }

    // 直接清除客户端cookie中的标记点数据 我直接留空应该没事
    SetClientCookie(client, g_hCookie, "");

    // 清除由该玩家生成的特殊感染者
    if (g_aSpawnedSI[client] != null)
    {
        for (int i = 0; i < g_aSpawnedSI[client].Length; i++)
        {
            int entity = EntRefToEntIndex(g_aSpawnedSI[client].Get(i));
            if (entity != -1 && IsValidEntity(entity))
            {
                AcceptEntityInput(entity, "Kill"); // 直接移除
            }
        }

        // 清空数组
        g_aSpawnedSI[client].Clear();
    }
}

//获取坐标点流程距离
float GetFlowFromPoint(float point[3])
{
    Address terrorNavPointer = L4D2Direct_GetTerrorNavArea(point);
    if (terrorNavPointer == Address_Null)
    {
        return 0.0;
    }
    return L4D2Direct_GetTerrorNavAreaFlow(terrorNavPointer);
}