
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"

#define MAX_PLAYERS 8      //所支持的最大玩家人数
#define CONFIG_DIR "configs/ExecCFG"

#define L4D2Team_None 0
#define L4D2Team_Spectator 1
#define L4D2Team_Survivor 2
#define L4D2Team_Infected 3

ConVar
    g_cvEnabled,
    g_cvDebugEnabled,
    g_cvExecPaths[MAX_PLAYERS],
    g_cvIgnoreSpec,
    g_cvIgnoreSur,
    g_cvIgnoreInf,
    g_cvIgnoreAdmin;

int
    g_iLastPlayerCount = 0;

Handle
    g_hDebounceTimer,
    g_hDebounceTimer2;

//bool g_bPlayerPutInServer;

public Plugin myinfo = 
{
    name = "DCE-Pro CFG Auto Loader",    //Dynamic Config Executor
    author = "Seiunsky Maomao",
    description = "服务器达到特定人数时,自动执行相对应人数的cfg文件.初次运行会在configs/ExecCFG文件里自动生成一次cfg文件.",
    version = PLUGIN_VERSION,
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("DCE_Enabled", "1", "插件开关.1开,0关.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvIgnoreSpec = CreateConVar("DCE_IgnoreSpec", "0", "人数累计是否忽略旁观?1是,0否.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvIgnoreSur = CreateConVar("DCE_IgnoreSur", "0", "人数累计是否忽略生还?1是,0否.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvIgnoreInf = CreateConVar("DCE_IgnoreInf", "0", "人数累计是否忽略特感?1是,0否.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvIgnoreAdmin = CreateConVar("DCE_IgnoreAdmin", "0", "人数累计是否忽略管理?1是,0否.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cvDebugEnabled = CreateConVar("dce_debug", "0", "调试开关.1开,0关.", FCVAR_NONE, true, 0.0, true, 1.0);

    for(int i = 0; i < MAX_PLAYERS; i++)
    {
        char convarName[32], defaultValue[PLATFORM_MAX_PATH], description[64];
        char configPath[PLATFORM_MAX_PATH];
        
        BuildPath(Path_SM, configPath, sizeof(configPath), "%s/player_%d.cfg", CONFIG_DIR, i+1);
        
        Format(convarName, sizeof(convarName), "sm_playercount_exec%d", i+1);
        Format(defaultValue, sizeof(defaultValue), "%s", configPath);
        Format(description, sizeof(description), "%d名玩家时执行的配置", i+1);
        
        g_cvExecPaths[i] = CreateConVar(convarName, defaultValue, description);
    }

    //HookEvent("player_connect_full", Event_PlayerConnectFull, EventHookMode_Post);
    //HookEvent("player_disconnect", Event_PlayerChange, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerChange, EventHookMode_Post);

    RegAdminCmd("sm_dce", Command_MainMenu, ADMFLAG_ROOT, "打开主菜单.");
    RegAdminCmd("sm_dcestatus", Command_Status, ADMFLAG_ROOT, "查看插件状态.");

    CreateConfigDirectory();    //文件夹创建
    CreateAllConfigFiles();     //配置文件创建

    //AutoExecConfig(true, "DCE_Pro");
}

//创建目录文件夹
void CreateConfigDirectory()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), CONFIG_DIR);
    
    if(!DirExists(path))    //文件夹不存在则创建
    {
        CreateDirectory(path, 511);
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("已创建配置目录: %s", path);
            PrintToServer("已创建配置目录: %s", path);
        }
    }
}

// 路径处理
void GetConfigPath(int count, char[] buffer, int maxlen)
{
    char configFile[64];
    Format(configFile, sizeof(configFile), "player_%d.cfg", count);
    BuildPath(Path_SM, buffer, maxlen, "%s/%s", CONFIG_DIR, configFile);
}

//目录配置创建
void CreateAllConfigFiles()
{
    for (int i = 1; i <= MAX_PLAYERS; i++)
    {
        char configPath[PLATFORM_MAX_PATH];
        GetConfigPath(i, configPath, sizeof(configPath));
        EnsureConfigFileExists(configPath);
    }
}

//确保配置文件存在，不存在则自动创建
void EnsureConfigFileExists(const char[] configPath)
{
    if (FileExists(configPath)) return;

    //提取人数数字,从0开始
    int playerCount = 0;
    for (int i = 1; i <= MAX_PLAYERS; i++)
    {
        char tempPath[PLATFORM_MAX_PATH];
        GetConfigPath(i, tempPath, sizeof(tempPath));
        if(StrEqual(configPath, tempPath))
        {
            playerCount = i;
            break;
        }
    }

    File file = OpenFile(configPath, "w");
    if (file != null)
    {
        //写入注释
        file.WriteLine("// *服务器内有%d名玩家时执行的配置内容.", playerCount);
        file.WriteLine("// *在这写入需要执行的cvar等.");
        file.WriteLine("// *例:");
        file.WriteLine("//sm_cvar z_tank_health 1600");
        file.WriteLine("//sm_cvar z_common_limit 15");
        file.WriteLine("//sm_cvar charger_pz_claw_dmg 8");
        file.WriteLine("//exec sourcemod/456/123.cfg");
        file.Close();

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("成功创建: %s", configPath);
            PrintToServer("成功创建: %s", configPath);
        }
    }
    else
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            LogError("配置文件: %s 创建失败,请检查相关目录权限.", configPath);
            PrintToServer("配置文件: %s 创建失败,请检查相关目录权限.", configPath);
        }
    }
}

//sm_dce命令菜单处理
Action Command_MainMenu(int i, int args)
{
    Menu menu = new Menu(MenuHandler_Main);
    //标题
    menu.SetTitle("DCE-Pro v%s", PLUGIN_VERSION);
    //内容
    menu.AddItem("toggle", g_cvEnabled.BoolValue ? "关闭插件" : "启用插件");
    menu.AddItem("ignorespec", g_cvIgnoreSpec.BoolValue ? "不忽略旁观" : "忽略旁观");
    menu.AddItem("ignoresur", g_cvIgnoreSur.BoolValue ? "不忽略生还" : "忽略生还");
    menu.AddItem("ignoreinf", g_cvIgnoreInf.BoolValue ? "不忽略特感" : "忽略特感");
    menu.AddItem("ignoreadmin", g_cvIgnoreAdmin.BoolValue ? "不忽略管理" : "忽略管理");
    menu.AddItem("status", "查看当前状态");
    menu.AddItem("reload", "重新加载配置");
    menu.ExitButton = true;
    
    menu.Display(i, 20);
    return Plugin_Handled;
}

//sm_dce命令菜单执行
int MenuHandler_Main(Menu menu, MenuAction action, int i, int item)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));
        
        if (StrEqual(info, "toggle"))
        {
            bool newState = !g_cvEnabled.BoolValue;     //取相反值
            g_cvEnabled.SetBool(newState);              //若true,newstate就是g_cvEnabled=0
            if (newState)    //只有当g_cvEnabled=0时进行切换才需要重载配置
            {
                ReloadPluginConfig();
            }
            PrintToChat(i, "\x04插件已\x05%s\x04.", newState ? "启用" : "禁用");
        }
        else if (StrEqual(info, "ignorespec"))
        {
            g_cvIgnoreSpec.SetBool(!g_cvIgnoreSpec.BoolValue);
            ReloadPluginConfig();
            PrintToChat(i, "\x04人数累计将\x05%s\x04旁观玩家.", g_cvIgnoreSpec.BoolValue ? "忽略" : "不忽略");
            FakeClientCommand(i, "sm_dcestatus");
        }
        else if (StrEqual(info, "ignoresur"))
        {
            g_cvIgnoreSur.SetBool(!g_cvIgnoreSur.BoolValue);
            ReloadPluginConfig();
            PrintToChat(i, "\x04人数累计将\x05%s\x04生还玩家.", g_cvIgnoreSur.BoolValue ? "忽略" : "不忽略");
            FakeClientCommand(i, "sm_dcestatus");
        }
        else if (StrEqual(info, "ignoreinf"))
        {
            g_cvIgnoreInf.SetBool(!g_cvIgnoreInf.BoolValue);
            ReloadPluginConfig();
            PrintToChat(i, "\x04人数累计将\x05%s\x04特感玩家.", g_cvIgnoreInf.BoolValue ? "忽略" : "不忽略");
            FakeClientCommand(i, "sm_dcestatus");
        }
        else if (StrEqual(info, "ignoreadmin"))
        {
            g_cvIgnoreAdmin.SetBool(!g_cvIgnoreAdmin.BoolValue);
            ReloadPluginConfig();
            PrintToChat(i, "\x04人数累计将\x05%s\x04管理员.", g_cvIgnoreAdmin.BoolValue ? "忽略" : "不忽略");
            FakeClientCommand(i, "sm_dcestatus");
        }
        else if (StrEqual(info, "status"))
        {
            FakeClientCommand(i, "sm_dcestatus");
        }
        else if (StrEqual(info, "reload"))
        {
            ReloadPluginConfig();
            PrintToChat(i, "\x04配置已重新加载!");
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

//sm_dcestatus命令处理
Action Command_Status(int i, int args)
{
    int currentPlayers = GetRealPlayerCount();

    char status[256];
    Format(status, sizeof(status), "\x04DCE-Pro:\n\x01• \x05插件状态: \x03%s \n\x01• \x05有效累计: \x03%d\x05人\n\x01• \x05忽略旁观: \x03%s\n\x01• \x05忽略生还: \x03%s\n\x01• \x05忽略特感: \x03%s\n\x01• \x05忽略管理: \x03%s", 
        g_cvEnabled.BoolValue ? "已启用" : "已禁用", 
        currentPlayers,
        g_cvIgnoreSpec.BoolValue ? "是" : "否",
        g_cvIgnoreSur.BoolValue ? "是" : "否",
        g_cvIgnoreInf.BoolValue ? "是" : "否",
        g_cvIgnoreAdmin.BoolValue ? "是" : "否");
    
    ReplyToCommand(i, status);
    return Plugin_Handled;
}

//重新加载配置处理
void ReloadPluginConfig()
{
    // 直接执行当前人数对应的配置文件
    int currentPlayers = GetRealPlayerCount();

    if (currentPlayers > 0)     //不存在0人及以下人数配置
    {
        ExecuteConfigForPlayers(currentPlayers);
    
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("已重载当前的%d人配置.", currentPlayers);
            PrintToServer("已重载当前的%d人配置.", currentPlayers);
        }
    }
}

/*
//地图切换,包含了过渡
public void OnMapEnd()
{
    if (g_bPlayerPutInServer)
    {
        g_bPlayerPutInServer = false;

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("触发OnMapEnd,更新:g_bPlayerPutInServer = false");
            PrintToServer("触发OnMapEnd,更新:g_bPlayerPutInServer = false");
        }
    }
}
*/

//玩家挤进服务器
public void OnClientPutInServer(int i)
{
    if (!g_cvEnabled.BoolValue) return;

    if (IsClient(i))
    {
        //如果有,先取消之前的定时器
        if (g_hDebounceTimer != null)
        {
            KillTimer(g_hDebounceTimer);
            g_hDebounceTimer = null;

            if (g_cvDebugEnabled.BoolValue)
            {
                LogMessage("已销毁旧计时器.");
                PrintToServer("已销毁旧计时器.");
            }
        }
        //然后再重新创建计时器
        g_hDebounceTimer = CreateTimer(0.2, Timer_DelayedCheck);

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("[%N]触发OnClientPutInServer事件.创建新计时器.", i);
            PrintToServer("[%N]触发OnClientPutInServer事件.创建新计时器.", i);
        }
    }
}

/*
//首批玩家完全连接进服务器时
public void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return;
    if (g_bPlayerPutInServer) return;

    if (!g_bPlayerPutInServer)
    {
        g_bPlayerPutInServer = true;

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("触发Event_PlayerConnectFull,更新:g_bPlayerPutInServer = true");
            PrintToServer("触发Event_PlayerConnectFull,更新:g_bPlayerPutInServer = true");
        }
    }
}
*/

//玩家开始断开连接时
public void OnClientDisconnect(int i)
{
    if (!g_cvEnabled.BoolValue) return;

    if (IsClient(i))
    {
        //如果有,先取消之前的定时器
        if (g_hDebounceTimer2 != null)
        {
            KillTimer(g_hDebounceTimer2);
            g_hDebounceTimer2 = null;

            if (g_cvDebugEnabled.BoolValue)
            {
                LogMessage("已销毁旧计时器.");
                PrintToServer("已销毁旧计时器.");
            }
        }
        //然后再重新创建计时器
        g_hDebounceTimer2 = CreateTimer(0.2, Timer_DelayedCheck);

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("玩家[%N]触发OnClientDisconnect事件.创建新计时器.", i);
            PrintToServer("玩家[%N]触发OnClientDisconnect事件.创建新计时器.", i);
        }
    }
}

/*
    仅处理玩家换队时,不处理客户端退出/进入服务器时的情况,
    避免回调共享计时器时创建新的2秒计时器而出现换队伍时短暂的计数出错.
*/
Action Event_PlayerChange(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvEnabled.BoolValue) return Plugin_Continue;
    //if (!g_bPlayerPutInServer) return Plugin_Continue;

    int i = GetClientOfUserId(event.GetInt("userid"));
    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    
    //确保只有换队事件能触发
    if (IsClient(i) && newTeam != oldTeam && newTeam != 0 && oldTeam != 0)
    {
        if (g_hDebounceTimer2 != null)
        {
            KillTimer(g_hDebounceTimer2);
            g_hDebounceTimer2 = null;

            if (g_cvDebugEnabled.BoolValue)
            {
                LogMessage("已销毁旧计时器.");
                PrintToServer("已销毁旧计时器.");
            }
        }
        //创建新的计时器
        g_hDebounceTimer2 = CreateTimer(0.2, Timer_DelayedCheck2);
        
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("[%N]触发Event_PlayerChange事件.创建新计时器.", i);
            PrintToServer("[%N]触发Event_PlayerChange事件.创建新计时器.", i);
        }
    }
    return Plugin_Continue;
}

// 如果存在正在连接的玩家，则创建2秒后重试的定时器
// 确保服务器没有处于连接中的玩家时，才会继续执行配置文件
Action Timer_DelayedCheck(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
    {
        return Plugin_Stop;
    }

    //重新置空,否则下一次计时器无法创建
    g_hDebounceTimer = null;

    //如果有玩家还在连接中
    if (HasPlayersConnecting())
    {
        //则触发2秒后重试的计时器
        g_hDebounceTimer = CreateTimer(2.0, Timer_DelayedCheck);
        
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("有玩家连接中,创建2秒后重试的计时器");
            PrintToServer("有玩家连接中,创建2秒后重试的计时器");
        }
        
        return Plugin_Stop;
    }

    if (g_cvDebugEnabled.BoolValue)
    {
        LogMessage("变动前 g_iLastPlayerCount = %d.", g_iLastPlayerCount);
        PrintToServer("变动前 g_iLastPlayerCount = %d.", g_iLastPlayerCount);
    }

    //之后重新计算人数
    int currentPlayers = GetRealPlayerCount();
    
    //对比看是不是和上次人数不一致
    if (currentPlayers != g_iLastPlayerCount)
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("人数发生变动: %d → %d",g_iLastPlayerCount, currentPlayers);
            PrintToServer("人数发生变动: %d → %d",g_iLastPlayerCount, currentPlayers);
        }
        //如果不一致，则重新更新人数，然后执行
        g_iLastPlayerCount = currentPlayers;
        ExecuteConfigForPlayers(currentPlayers);
    }
    
    return Plugin_Stop;
}

Action Timer_DelayedCheck2(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
    {
        return Plugin_Stop;
    }

    //重新置空,否则下一次计时器无法创建
    g_hDebounceTimer2 = null;

    if (g_cvDebugEnabled.BoolValue)
    {
        LogMessage("变动前 g_iLastPlayerCount = %d.", g_iLastPlayerCount);
        PrintToServer("变动前 g_iLastPlayerCount = %d.", g_iLastPlayerCount);
    }

    //之后重新计算人数
    int currentPlayers = GetRealPlayerCount();
    
    //对比看是不是和上次人数不一致
    if (currentPlayers != g_iLastPlayerCount)
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("人数发生变动: %d → %d",g_iLastPlayerCount, currentPlayers);
            PrintToServer("人数发生变动: %d → %d",g_iLastPlayerCount, currentPlayers);
        }
        //如果不一致，则重新更新人数，然后执行
        g_iLastPlayerCount = currentPlayers;
        ExecuteConfigForPlayers(currentPlayers);
    }
    
    return Plugin_Stop;
}

//执行相应配置人数cfg
void ExecuteConfigForPlayers(int currentPlayers)
{
    if (currentPlayers <= 0 || currentPlayers > MAX_PLAYERS) return;

    char configPath[PLATFORM_MAX_PATH];
    GetConfigPath(currentPlayers, configPath, sizeof(configPath));

    if (!FileExists(configPath))
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            LogError("配置文件: %s 不存在,请检查相关目录权限.", configPath);
            PrintToServer("配置文件: %s 不存在,请检查相关目录权限.", configPath);
        }
        return;
    }

    //该配置存在就直接执行
    ExecuteConfigCommands(configPath);
}

//执行cfg中的配置
void ExecuteConfigCommands(const char[] configPath)
{
    File file = OpenFile(configPath, "r");
    if (file == null)
    {
        if (g_cvDebugEnabled.BoolValue)
        {
            LogError("无法打开配置文件: %s", configPath);
            PrintToServer("无法打开配置文件: %s", configPath);
        }
        return;
    }

    char line[256];
    while (!file.EndOfFile())
    {
        if (!file.ReadLine(line, sizeof(line)))
            break;

        TrimString(line);
        ReplaceString(line, sizeof(line), "\n", "");
        ReplaceString(line, sizeof(line), "\r", "");

        if (strlen(line) == 0 || line[0] == '/')
            continue;

        ServerCommand("%s", line);

        if (g_cvDebugEnabled.BoolValue)
        {
            LogMessage("已执行命令: %s", line);
            PrintToServer("已执行命令: %s", line);
        }
    }

    delete file;

    if (g_cvDebugEnabled.BoolValue)
    {
        LogAction(0, -1, "成功执行配置文件: %s", configPath);
        PrintToServer("成功执行配置文件: %s", configPath);
    }
}

//玩家是否处于连接状态
bool HasPlayersConnecting()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        //已经建立连接 + 不是bot + 客户端还未载入游戏的,则判定为正在连接中
        if(IsClientConnected(i) && !IsFakeClient(i) && !IsClientInGame(i))
        {
            return true;
        }
    }
    return false;
}

//客户端累计
int GetRealPlayerCount()
{
    int count = 0;      //初始化为0,从0开始
    bool ignoreSpec = g_cvIgnoreSpec.BoolValue;
    bool ignoreAdmin = g_cvIgnoreAdmin.BoolValue;
    bool ignoreSur = g_cvIgnoreSur.BoolValue;
    bool ignoreInf = g_cvIgnoreInf.BoolValue;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        //非玩家忽略
        if (!IsValidPlayer(i))
            continue;
            
        //若使用管理忽略,则
        if (ignoreAdmin && IsClientAdmin(i))
            continue;
        
        //若使用旁观忽略,则
        if (ignoreSpec && IsValidSpec(i))
            continue;

        //若使用生还忽略,则
        if (ignoreSur && IsValidSur(i))
            continue;

        //若使用特感忽略,则
        if (ignoreInf && IsValidInf(i))
            continue;
            
        count++;    //最终累计符合要求人数
    }

    if (g_cvDebugEnabled.BoolValue)
    {
        LogMessage("累计人数:%d", count);
        PrintToServer("累计人数:%d", count);
    }

    return count;   //返回累计人数
}

//是游戏内有效玩家
bool IsValidPlayer(int i)
{
    return i > 0 && i <= MaxClients && IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i) && !IsClientReplay(i) && IsClientConnected(i);
}

//是个玩家就行
bool IsClient(int i)
{
    return i > 0 && i <= MaxClients && !IsFakeClient(i) && !IsClientSourceTV(i) && !IsClientReplay(i);
}

//是旁观
bool IsValidSpec(int i)
{
    return IsValidPlayer(i) && GetClientTeam(i) == 1;
}

//是生还
bool IsValidSur(int i)
{
    return IsValidPlayer(i) && GetClientTeam(i) == 2;
}

//是特感
bool IsValidInf(int i)
{
    return IsValidPlayer(i) && GetClientTeam(i) == 3;
}

//是管理
bool IsClientAdmin(int i)
{
    //clients.inc
    AdminId admin = GetUserAdmin(i);
    return IsValidPlayer(i) && (admin != INVALID_ADMIN_ID);     //如果玩家没有管理权限将会返回INVALID_ADMIN_ID
}