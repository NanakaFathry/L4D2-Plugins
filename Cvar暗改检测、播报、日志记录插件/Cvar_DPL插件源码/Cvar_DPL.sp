#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

bool g_bIsRecorded[MAXPLAYERS + 1];

//日志路径
#define LOG_PATH "addons/sourcemod/logs/AAAcvar/cvar.log"

public Plugin myinfo = 
{
    name = "Cvar违规检测-播报-记录",
    author = "Seiunsky Maomao",
    description = "播报,及记录客户端cvar违规信息到自定义日志文件.",
    version = "1.1",
    url = "https://github.com/NanakaFathry/L4D2-Plugins"
}

public void OnPluginStart()
{
    //日志目录创建
    CreateDirectoryTree(LOG_PATH);
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bIsRecorded[i])
        {
            g_bIsRecorded[i] = false;
        }
    }
}

public void OnClientPutInServer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bIsRecorded[i])
        {
            g_bIsRecorded[i] = false;
        }
    }
}

public void OnClientDisconnect(int i)
{
    if (i > 0 && i <= MaxClients)
    {
        if (g_bIsRecorded[i])
        {
            g_bIsRecorded[i] = false;
        }
    }
}

//ClientSettings.sp / trackclientcvar_zm.sp 里的函数
public void CLS_OnCvarViolation(int i, const char[] cvar, float value, float min, float max, int action)
{
    //如果记录过为true则返回
    if (g_bIsRecorded[i]) return;
    
    //记录日志并设置为true
    LogCvarViolation(i, cvar, value, min, max);
    g_bIsRecorded[i] = true;
}

//记录日志
static void LogCvarViolation(int i, const char[] cvar, float value, float min, float max)
{
    //玩家steam32id
    char steamId[32];
    if (!GetClientAuthId(i, AuthId_Steam2, steamId, sizeof(steamId)))
    {
        strcopy(steamId, sizeof(steamId), "未知SteamID");
    }
    
    //玩家名称
    char clientName[MAX_NAME_LENGTH];
    GetClientName(i, clientName, sizeof(clientName));
    
    //打开日志文件
    File file = OpenFile(LOG_PATH, "a");
    if (file == null)
    {
        //如果错误,此时应该是权限问题
        LogError("无法打开日志文件: %s", LOG_PATH);
        return;
    }
    
    //时间
    char timeBuffer[64];
    FormatTime(timeBuffer, sizeof(timeBuffer), "%Y-%m-%d %H:%M:%S");
    
    // 写入
    file.WriteLine("[%s]", timeBuffer);
    file.WriteLine("玩家ID: %s", clientName);
    file.WriteLine("SteamID: %s", steamId);
    file.WriteLine("违规Cvar: %s", cvar);
    file.WriteLine("违规Cvar数值: %.0f", value);
    file.WriteLine("允许的最小值: %.0f", min);
    file.WriteLine("允许的最大值: %.0f", max);
    file.WriteLine(""); //空行分隔
    
    //关闭文件
    delete file;
    
    //输出
    PrintToChatAll("\x01检测到Cvar违规:");
    PrintToChatAll("\x05玩家：\x04%s \x01[\x04%s\x01]", clientName, steamId);
    PrintToChatAll("\x05违规Cvar：\x04%s \x01= \x04%.0f", cvar, value);
    PrintToChatAll("\x05允许的数值：\x04%.0f \x01~ \x04%.0f", min, max);
    //PrintToChatAll("\x05已同步服务器日志.");
}

static void CreateDirectoryTree(const char[] path)
{
    char dirPath[PLATFORM_MAX_PATH];
    strcopy(dirPath, sizeof(dirPath), path);
    
    int pos = FindCharInString(dirPath, '/', true);
    if (pos == -1)
    {
        pos = FindCharInString(dirPath, '\\', true);
    }
    
    if (pos != -1)
    {
        dirPath[pos] = '\0';
        
        //创建目录树
        CreateDirectories(dirPath);
    }
}

static void CreateDirectories(const char[] path)
{
    char dirPath[PLATFORM_MAX_PATH];
    strcopy(dirPath, sizeof(dirPath), path);
    
    //将正斜杠替换为反斜杠
    ReplaceString(dirPath, sizeof(dirPath), "/", "\\");
    
    //分割路径并创建目录
    char currentPath[PLATFORM_MAX_PATH];
    currentPath[0] = '\0';
    
    int len = strlen(dirPath);
    for (int i = 0; i < len; i++)
    {
        if (dirPath[i] == '\\')
        {
            if (currentPath[0] != '\0' && !DirExists(currentPath))
            {
                CreateDirectory(currentPath, 511);
            }
        }
        
        Format(currentPath, sizeof(currentPath), "%s%c", currentPath, dirPath[i]);
    }
    
    //创建目录
    if (currentPath[0] != '\0' && !DirExists(currentPath))
    {
        CreateDirectory(currentPath, 511);
    }
}
