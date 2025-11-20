#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <l4d2util>
#include <left4dhooks>

#define CONFIG_PATH "data/BieShuoZangHua.txt"

ArrayList
	g_ReplaceList,
	g_Mode3Messages;

ConVar
	g_cvPluginEnabled,
	g_cvAdminImmunity,
	g_cvAutoCiXiaoGui,
	g_cvMode3Interval,
	g_cvDebug;

bool
	g_bPlayerPutInServer,
	g_bIsChanged1[MAXPLAYERS + 1],
	g_bIsChanged2[MAXPLAYERS + 1];

Handle
	g_hControled[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "文明聊天,人人有责",
	author = "Seiunsky Maomao",
	description = "检测,拦截并直接替换玩家相应聊天内容,主要用来反脏话和敏感言论.亦或是促进交流文明.",
	version = "1.3",
	url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
	g_ReplaceList = new ArrayList(ByteCountToCells(256));
	g_Mode3Messages = new ArrayList(ByteCountToCells(256));
	
	g_cvPluginEnabled = CreateConVar("sm_bszh_enabled", "1", "插件开关.(1开,0关.)", _, true, 0.0, true, 1.0);
	g_cvAdminImmunity = CreateConVar("sm_bszh_admin_immunity", "1", "管理员说的道理?(1是,0否.)", _, true, 0.0, true, 1.0);
	g_cvAutoCiXiaoGui = CreateConVar("sm_bszh_auto_talk", "1", "被控时是否自动发送模式3配置的消息?(1是,0否.)", _, true, 0.0, true, 1.0);
	g_cvMode3Interval = CreateConVar("sm_bszh_m3_at_int", "1.0", "模式3配置字词消息的发送间隔(秒).", _, true, 0.1);

	g_cvDebug = CreateConVar("sm_bszh_debug", "0", "调试开关.(1开,0关.)", _, true, 0.0, true, 1.0);
	
	RegAdminCmd("sm_bszh_reload", Command_BSZHReload, ADMFLAG_ROOT, "管理员重载配置规则.");
	
	AddCommandListener(OnSayCommand, "say");
	AddCommandListener(OnSayCommand, "say_team");

	HookEvent("player_connect_full", Event_PlayerConnectFull, EventHookMode_Post);
	HookEvent("tongue_grab", Event_Controled, EventHookMode_Post);
	HookEvent("tongue_release", Event_ControlEnd, EventHookMode_Post);
	HookEvent("lunge_pounce", Event_Controled, EventHookMode_Post);
	HookEvent("pounce_end", Event_ControlEnd, EventHookMode_Post);
	HookEvent("jockey_ride", Event_Controled, EventHookMode_Post);
	HookEvent("jockey_ride_end", Event_ControlEnd, EventHookMode_Post);
	HookEvent("charger_pummel_start", Event_Controled, EventHookMode_Post);
	HookEvent("charger_pummel_end", Event_ControlEnd, EventHookMode_Post);

	LoadReplaceConfig();

	AutoExecConfig(true, "BieShuoZangHua");
}

//首次玩家进服
public void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bPlayerPutInServer)
		return;

	LoadReplaceConfig();
	g_bPlayerPutInServer = true;

	if (g_cvDebug.BoolValue)
	{
		PrintToServer("Event_PlayerConnectFull触发!");
		PrintToServer("载入规则,g_bPlayerPutInServer更改为true.");
	}
}

//地图切换/过渡,确保中间有更新检测词汇则换图后会生效
public void OnMapEnd()
{
	if (g_bPlayerPutInServer)
	{
		g_bPlayerPutInServer = false;

		if (g_cvDebug.BoolValue)
		{
			PrintToServer("g_bPlayerPutInServer更改为false.");
		}
	}
}

//文件读取和创建
void LoadReplaceConfig()
{
	g_ReplaceList.Clear();
	g_Mode3Messages.Clear();
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CONFIG_PATH);
	
	//如果文件不存在则创建
	if (!FileExists(path))
	{
		CreateDefaultConfig(path);

		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 已成功创建文件:%s", path);
		}
	}
	
	File file = OpenFile(path, "r");
	if (file == null)
	{
		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 无法打开配置文件:%s,请检查系统读写权限!", path);
		}

		return;
	}
	
	char line[256];
	int lineCount = 0;
	int mode3Count = 0;
	
	while (!file.EndOfFile() && file.ReadLine(line, sizeof(line)))
	{
		//移除换行符
		ReplaceString(line, sizeof(line), "\n", "");
		ReplaceString(line, sizeof(line), "\r", "");
		TrimString(line);
		
		//跳过空行和注释
		if (StrEqual(line, "") || line[0] == ';' || line[0] == '/')
			continue;

		char message[256];
		
		//验证格式,先验证模式3
		if (IsValidMode3Line(line, message, sizeof(message)))
		{
			g_Mode3Messages.PushString(message);
			mode3Count++;
			/*
			if (g_cvDebug.BoolValue)
			{
				PrintToServer("[!] 加载模式3消息[%d条]: %s", mode3Count, message);
			}
			*/
		}
		//后验证模式1和2的格式
		else if (IsValidReplaceLine(line))
		{
			g_ReplaceList.PushString(line);
			lineCount++;
		}
		else
		{
			if (g_cvDebug.BoolValue)
			{
				PrintToServer("[!] 无效的配置行:%s", line);
			}
		}
	}
	
	delete file;

	if (g_cvDebug.BoolValue)
	{
		PrintToServer("[!] 成功加载: %d条模式1和2的规则. | %d条模式3的规则.", lineCount, mode3Count);
	}
}

//解析配置,只用于模式1和模式2
bool IsValidReplaceLine(const char[] line)
{
	char parts[3][128];
	int count = ExplodeString(line, "_", parts, sizeof(parts), sizeof(parts[]));
	//配置不完全
	if (count != 3)
		return false;
	
	//检查第3部分,模式1还是2
	int mode = StringToInt(parts[2]);
	return (mode == 1 || mode == 2);
}

//解析配置,只用于模式3
bool IsValidMode3Line(const char[] line, char[] message, int maxlen)
{
	char parts[2][256];
	int count = ExplodeString(line, "_", parts, sizeof(parts), sizeof(parts[]));
	//配置不完全时
	if (count != 2)
		return false;
	
	//检查第2部分是否为模式3
	int mode = StringToInt(parts[1]);
	if (mode != 3)
		return false;
	
	//如果是则复制
	strcopy(message, maxlen, parts[0]);
	TrimString(message);
	
	return (strlen(message) > 0);
}

//重载配置命令
public Action Command_BSZHReload(int client, int args)
{
	LoadReplaceConfig();
	CPrintToChat(client, "[!] 配置已重载!");

	return Plugin_Handled;
}

//截胡聊天消息
public Action OnSayCommand(int client, const char[] command, int argc)
{
	if (!g_cvPluginEnabled.BoolValue)
		return Plugin_Continue;
	
	if (g_cvAdminImmunity.BoolValue && IsClientAdmin(client))
		return Plugin_Continue;

	if (!IsValidClient(client))
		return Plugin_Continue;

	if (g_bIsChanged1[client])
	{
		g_bIsChanged1[client] = false;
		
		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 消息已替换.");
		}
		
		return Plugin_Continue;
	}

	if (g_bIsChanged2[client])
	{
		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 消息无需替换.");
		}
		
		return Plugin_Continue;
	}
	
	//截取原消息
	char message[256];
	GetCmdArgString(message, sizeof(message));

	StripQuotes(message);
	//TrimString(message);

	//替换消息
	char newMsg[256];
	strcopy(newMsg, sizeof(newMsg), message);
	bool replaced = ProcessMessageReplacement(newMsg, sizeof(newMsg), message);
	//最终替换
	if (replaced && !StrEqual(newMsg, message))
	{
		//标记已替换
		g_bIsChanged1[client] = true;

		//用这种方式来代发消息即可
		if (StrEqual(command, "say"))
		{
			//公屏消息 
			FakeClientCommand(client, "say %s", newMsg);
		}
		else if (StrEqual(command, "say_team"))
		{
			//团队消息
			FakeClientCommand(client, "say_team %s", newMsg);
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//消息替换
bool ProcessMessageReplacement(char[] buffer, int maxlen, const char[] message)
{
	bool replaced = false;
	char tempBuffer[256];
	strcopy(tempBuffer, sizeof(tempBuffer), message);
	
	//移除特殊字符并转小写,放行命令
	char processedMsg[256];
	strcopy(processedMsg, sizeof(processedMsg), message);
	if (g_cvDebug.BoolValue)
	{
		PrintToServer("[!] 原始消息:[%s]", processedMsg);
	}

	//是否为命令
	char commandCheck[256];
	strcopy(commandCheck, sizeof(commandCheck), processedMsg);
	TrimString(commandCheck);   //去除首尾空格
	if (strlen(commandCheck) > 0 && (commandCheck[0] == '!' || commandCheck[0] == '/'))
	{
		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 是命令前缀,去除前空格并输出:[%s]", commandCheck);
		}
		strcopy(buffer, maxlen, commandCheck);
		return true;
	}

	//非命令继续处理
	RemoveAllSpecialCharacters(processedMsg, sizeof(processedMsg));
	StringToLower(processedMsg, sizeof(processedMsg));
	if (g_cvDebug.BoolValue)
	{
		PrintToServer("[!] 最终处理:[%s]", processedMsg);
	}
	
	for (int i = 0; i < g_ReplaceList.Length; i++)
	{
		char replaceData[3][256];
		g_ReplaceList.GetString(i, replaceData[0], sizeof(replaceData[]));
		
		int count = ExplodeString(replaceData[0], "_", replaceData, sizeof(replaceData), sizeof(replaceData[]));
		if (count != 3)
			continue;
		
		char originalWord[128], replaceWord[128], modeStr[8];
		strcopy(originalWord, sizeof(originalWord), replaceData[0]);
		strcopy(replaceWord, sizeof(replaceWord), replaceData[1]);
		strcopy(modeStr, sizeof(modeStr), replaceData[2]);
		
		int mode = StringToInt(modeStr);

		if (mode == 1)
		{
			if (ContainsWordAndReplace(tempBuffer, sizeof(tempBuffer), originalWord, replaceWord, processedMsg))
			{
				replaced = true;
				break;	  //替换后跳出循环
			}
		}
		else if (mode == 2)
		{
			if (ContainsAllCharactersOrWords(processedMsg, originalWord))
			{
				strcopy(tempBuffer, sizeof(tempBuffer), replaceWord);
				replaced = true;
				break;	  //替换后跳出循环
			}
		}
	}
	//替换
	if (replaced)
	{
		strcopy(buffer, maxlen, tempBuffer);
		return true;
	}
	//否则无需替换
	return false;
}

//模式1替换逻辑
bool ContainsWordAndReplace(char[] message, int maxlen, const char[] originalWord, const char[] replaceWord, const char[] processedMsg)
{
	if (StrContains(processedMsg, originalWord, false) != -1)
	{
		//在预处理后的消息上进行替换
		char tempProcessed[256];
		strcopy(tempProcessed, sizeof(tempProcessed), processedMsg);
		ReplaceString(tempProcessed, sizeof(tempProcessed), originalWord, replaceWord, false);
		
		//将替换后的结果复制回原始消息
		strcopy(message, maxlen, tempProcessed);

		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 关键词:[%s] → 替换为:[%s]", originalWord, replaceWord);
			PrintToServer("[!] 替换后消息:[%s]", message);
		}
		return true;
	}
	
	if (g_cvDebug.BoolValue)
	{
		PrintToServer("[!] 关键词:[%s]未检出", originalWord);
	}
	return false;
}

//模式2替换逻辑
bool ContainsAllCharactersOrWords(const char[] message, const char[] keyword)
{
	char tempKeyword[128];
	strcopy(tempKeyword, sizeof(tempKeyword), keyword);
	
	//逗号分隔多个关键词语
	if (StrContains(keyword, ",", false) != -1)
	{
		char words[32][64];
		int wordCount = ExplodeString(keyword, ",", words, sizeof(words), sizeof(words[]));

		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 原始关键词=[%s] 分解为%d个词", keyword, wordCount);
		}
		
		if (wordCount > 0)
		{
			int foundCount = 0;
			//遍历每个词语
			for (int i = 0; i < wordCount; i++)
			{
				TrimString(words[i]);   //去除首空格
				
				//用关键词进行比对
				if (strlen(words[i]) > 0 && StrContains(message, words[i], false) != -1)
				{
					foundCount++;
					if (g_cvDebug.BoolValue)
					{
						PrintToServer("[!] 找到关键词[%s]在消息中.", words[i]);
					}
				}
				else
				{
					if (g_cvDebug.BoolValue)
					{
						PrintToServer("[!] 未找到关键词[%s]在消息中.", words[i]);
					}
				}
			}
			//如果所有词语都在消息中找到则返回true
			return (foundCount == wordCount);
		}
	}
	else
	{
		//单个关键词则检测是否在消息中出现即可
		return (StrContains(message, tempKeyword, false) != -1);
	}
	return false;
}

//计时器g_hControled[MAXPLAYERS + 1]回调
Action Mode3MessageTimer(Handle timer, DataPack pack)
{
	//解包
	pack.Reset();
	int victim = GetClientOfUserId(pack.ReadCell());
	//delete pack;	//不需要删除包,计时器杀死后也会跟着杀掉

	SendMode3Message(victim);

	return Plugin_Continue;
}

//模式3逻辑
void SendMode3Message(int client)
{
	if (g_Mode3Messages.Length == 0)
	{
		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 模式3字词未配置或配置错误!!");
			PrintToServer("[!] 请打开addons/sourcemod/data/BieShuoZangHua.txt进行重新配置.");
		}

		return;
	}

	if (!g_bIsChanged2[client])
	{
		g_bIsChanged2[client] = true;

		//随机选择一条模式3消息即可
		int randomIndex = GetRandomInt(0, g_Mode3Messages.Length - 1);
		char randomMsg[256];
		g_Mode3Messages.GetString(randomIndex, randomMsg, sizeof(randomMsg));

		FakeClientCommand(client, "say %s", randomMsg);
		//必须在FakeClientCommand输出之后才改为true

		g_bIsChanged2[client] = false;

		if (g_cvDebug.BoolValue)
		{
			PrintToServer("[!] 玩家%N被特感控制,发送模式3消息: %s", client, randomMsg);
		}
	}
}

//特感控制发生时执行
public void Event_Controled(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvAutoCiXiaoGui.BoolValue || !g_cvPluginEnabled.BoolValue)
		return;

	int victim = GetClientOfUserId(event.GetInt("victim"));
	int attacker = GetClientOfUserId(event.GetInt("userid"));

	if (!IsClient(attacker) || !IsClient(victim) || !IsInfected(attacker) || !IsSurvivor(victim))
	{
		return;
	}

	//创建循环计时器(g_hControled[MAXPLAYERS + 1])回调到Mode3MessageTimer函数
	if (IsCTRLSI(attacker) && g_hControled[victim] == null && g_cvMode3Interval.FloatValue > 0.0)
	{
		float M3Interval = g_cvMode3Interval.FloatValue;

		DataPack pack1 = new DataPack();
		pack1.WriteCell(GetClientUserId(victim));
		g_hControled[victim] = CreateTimer(M3Interval, Mode3MessageTimer, pack1, TIMER_REPEAT);
	}
}

//特感控制结束时执行
public void Event_ControlEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvAutoCiXiaoGui.BoolValue || !g_cvPluginEnabled.BoolValue)
		return;

	int victim = GetClientOfUserId(event.GetInt("victim"));

	//杀死计时器g_hControled[MAXPLAYERS + 1]
	if (IsClient(victim) && g_hControled[victim] != null)
	{
		KillTimer(g_hControled[victim]);
		g_hControled[victim] = null;
	}
	
	//结束控制时重置g_bIsChanged2
	if (g_bIsChanged2[victim])
	{
		g_bIsChanged2[victim] = false;
	}
}

//预写入默认配置
void CreateDefaultConfig(const char[] path)
{
	//write
	File file = OpenFile(path, "w");
	if (file == null)
		return;
	//预写入内容
	file.WriteLine("//[和谐规则配置]");
	file.WriteLine("; [!]检测上,会自动转化小写再去除特殊符号,最后再用于检测,因此使用小写即可.");
	file.WriteLine("; [!]配置可用双斜杠(//)或分号(;)来进行注释.");
	file.WriteLine("//配置格式:");
	file.WriteLine(";	   [模式1/2]被检测字词_替换字词_模式1/2");
	file.WriteLine(";	   [模式3]被控时发送的字词_模式3");
	file.WriteLine("//模式:");
	file.WriteLine(";	   1=只替换相应字词.");
	file.WriteLine(";	   2=满足全部被检测字词则直接替换整句,多个被检测字词之间可用逗号(,)分隔.");
	file.WriteLine(";	   3=被特感控时自动发送的字词(多条配置时随机选择其一).");
	file.WriteLine("");
	file.WriteLine(";模式3配置:");
	file.WriteLine("哦哦♡齁齁齁齁齁♡♡_3");
	file.WriteLine("哦齁齁♡老资历好舒胡♡♡_3");
	file.WriteLine("哦齁齁齁齁齁齁♡♡♡要去了♡~~_3");
	file.WriteLine("杂鱼♡~才...才不舒胡♡♡♡_3");
	file.WriteLine("哦齁齁要去了♡~要去了♡♡♡~~_3");
	file.WriteLine("//救我!救我!!_3");
	file.WriteLine("");
	file.WriteLine(";模式1/模式2配置:");
	file.WriteLine("nt_Nice Try!!_1");
	file.WriteLine("nao,tan_Nice Try!!_2");
	file.WriteLine("nc_杂鱼♡~_1");
	file.WriteLine("nao,can_Nice Try!!_2");
	file.WriteLine("fuck_杂鱼♡~_2");
	file.WriteLine("gg_Good Game!!_1");
	file.WriteLine("sb_杂鱼♡~_1");
	file.WriteLine("傻,逼_哦哦♡齁齁齁齁齁齁♡♡_2");
	file.WriteLine("sha,b_哦哦♡齁齁齁齁齁齁♡♡_2");
	file.WriteLine("s,bi_***_2");
	file.WriteLine("sa,b_***_2");
	file.WriteLine("傻,b_***_2");
	file.WriteLine("sha,逼_***_2");
	file.WriteLine("sa,逼_***_2");
	file.WriteLine("沙,比_***_2");
	file.WriteLine("sha,比_***_2");
	file.WriteLine("sa,比_***_2");
	file.WriteLine("沙,b_***_2");
	file.WriteLine("阐,述,你_***_2");
	file.WriteLine("nm_我妈_1");
	file.WriteLine("n,d,m_***_2");
	file.WriteLine("你,妈_哦哦♡齁齁齁齁齁齁♡♡_2");
	file.WriteLine("你,麻_***_2");
	file.WriteLine("你,玛_***_2");
	file.WriteLine("ni,ma_***_2");
	file.WriteLine("你,m_***_2");
	file.WriteLine("n,妈_***_2");
	file.WriteLine("尼,玛_***_2");
	file.WriteLine("尼,马_***_2");
	file.WriteLine("拟,马_***_2");
	file.WriteLine("拟,玛_***_2");
	file.WriteLine("泥,马_***_2");
	file.WriteLine("泥,玛_***_2");
	file.WriteLine("你,爸_***_2");
	file.WriteLine("你,爹_***_2");
	file.WriteLine("尼,妈_***_2");
	file.WriteLine("泥,妈_***_2");
	file.WriteLine("拟,妈_***_2");
	file.WriteLine("尼,m_***_2");
	file.WriteLine("泥,m_***_2");
	file.WriteLine("拟,m_***_2");
	file.WriteLine("逆,蝶_***_2");
	file.WriteLine("逆,碟_***_2");
	file.WriteLine("嫩,碟_***_2");
	file.WriteLine("嫩,蝶_***_2");
	file.WriteLine("逆,妈_***_2");
	file.WriteLine("逆,麻_***_2");
	file.WriteLine("嫩,妈_***_2");
	file.WriteLine("嫩,麻_***_2");
	file.WriteLine("嫩,m_***_2");
	file.WriteLine("逆,m_***_2");
	file.WriteLine("司,马_***_2");
	file.WriteLine("司,m_***_2");
	file.WriteLine("si,m_***_2");
	file.WriteLine("s,ma_***_2");
	file.WriteLine("s,马_***_2");
	file.WriteLine("si,马_***_2");
	file.WriteLine("死,妈_***_2");
	file.WriteLine("死,马_***_2");
	file.WriteLine("没,马_***_2");
	file.WriteLine("没,妈_***_2");
	file.WriteLine("没,麻_***_2");
	file.WriteLine("没,ma_***_2");
	file.WriteLine("没,m_***_2");
	file.WriteLine("mei,马_***_2");
	file.WriteLine("mei,ma_***_2");
	file.WriteLine("煞,笔_***_2");
	file.WriteLine("砂,笔_***_2");
	file.WriteLine("啥,比_***_2");
	file.WriteLine("沙,碧_***_2");
	file.WriteLine("沙,币_***_2");
	file.WriteLine("煞,b_***_2");
	file.WriteLine("砂,b_***_2");
	file.WriteLine("啥,b_***_2");
	file.WriteLine("沙,b_***_2");
	file.WriteLine("沙,b_***_2");
	file.WriteLine("s,笔_***_2");
	file.WriteLine("s,笔_***_2");
	file.WriteLine("s,比_***_2");
	file.WriteLine("s,碧_***_2");
	file.WriteLine("s,币_***_2");
	file.WriteLine("纱,布_***_2");
	file.WriteLine("纱,b_***_2");
	file.WriteLine("s,布_***_2");
	file.WriteLine("妈,逼_***_2");
	file.WriteLine("m,逼_***_2");
	file.WriteLine("妈,b_***_2");
	file.WriteLine("麻,痹_***_2");
	file.WriteLine("麻,b_***_2");
	file.WriteLine("m,痹_***_2");
	file.WriteLine("索,嗨_***_2");
	file.WriteLine("臭,逼_***_2");
	file.WriteLine("臭,嗨_***_2");
	
	delete file;
}

//是否有效玩家,排除bot
bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client));
}

//是否有效客户端,包括bot
bool IsClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client) && !IsClientReplay(client));
}

//4只控制型特感判断,包括bot
bool IsCTRLSI(int client)
{
	return (IsClient(client) && IsInfected(client) && (GetInfectedClass(client) == 1 || GetInfectedClass(client) == 3 || GetInfectedClass(client) == 5 || GetInfectedClass(client) == 6));
}

//是否管理,排除bot
bool IsClientAdmin(int client)
{
	if (!IsValidClient(client))
		return false;
	
	AdminId admin = GetUserAdmin(client);
	return (admin != INVALID_ADMIN_ID);
}

//将全部字母转换为小写
void StringToLower(char[] buffer, int maxlen)
{
	int len = strlen(buffer);
	if (len >= maxlen) len = maxlen - 1;
	
	for (int i = 0; i < len; i++)
	{
		buffer[i] = CharToLower(buffer[i]);
	}
}

//移除特殊字符
void RemoveAllSpecialCharacters(char[] buffer, int maxlen)
{
	ReplaceString(buffer, maxlen, " ", "", false);
	ReplaceString(buffer, maxlen, ",", "", false);
	ReplaceString(buffer, maxlen, ".", "", false);
	ReplaceString(buffer, maxlen, "/", "", false);
	ReplaceString(buffer, maxlen, "\\", "", false);
	ReplaceString(buffer, maxlen, ";", "", false);
	ReplaceString(buffer, maxlen, ":", "", false);
	ReplaceString(buffer, maxlen, "|", "", false);
	ReplaceString(buffer, maxlen, "，", "", false);
	ReplaceString(buffer, maxlen, "。", "", false);
	ReplaceString(buffer, maxlen, "、", "", false);
	ReplaceString(buffer, maxlen, "；", "", false);
	ReplaceString(buffer, maxlen, "：", "", false);
	ReplaceString(buffer, maxlen, "~", "", false);
	ReplaceString(buffer, maxlen, "@", "", false);
	ReplaceString(buffer, maxlen, "#", "", false);
	ReplaceString(buffer, maxlen, "$", "", false);
	ReplaceString(buffer, maxlen, "%", "", false);
	ReplaceString(buffer, maxlen, "^", "", false);
	ReplaceString(buffer, maxlen, "&", "", false);
	ReplaceString(buffer, maxlen, "*", "", false);
	ReplaceString(buffer, maxlen, "(", "", false);
	ReplaceString(buffer, maxlen, ")", "", false);
	ReplaceString(buffer, maxlen, "_", "", false);
	ReplaceString(buffer, maxlen, "-", "", false);
	ReplaceString(buffer, maxlen, "+", "", false);
	ReplaceString(buffer, maxlen, "=", "", false);
	ReplaceString(buffer, maxlen, ".", "", false);
	ReplaceString(buffer, maxlen, "`", "", false);
	ReplaceString(buffer, maxlen, "<", "", false);
	ReplaceString(buffer, maxlen, ">", "", false);
	ReplaceString(buffer, maxlen, "《", "", false);
	ReplaceString(buffer, maxlen, "》", "", false);
	ReplaceString(buffer, maxlen, "\"", "", false);
	ReplaceString(buffer, maxlen, "'", "", false);
	ReplaceString(buffer, maxlen, "＂", "", false);
	ReplaceString(buffer, maxlen, "＇", "", false);
	ReplaceString(buffer, maxlen, "「", "", false);
	ReplaceString(buffer, maxlen, "」", "", false);
	ReplaceString(buffer, maxlen, "『", "", false);
	ReplaceString(buffer, maxlen, "』", "", false);
	ReplaceString(buffer, maxlen, "“", "", false);
	ReplaceString(buffer, maxlen, "”", "", false);
	ReplaceString(buffer, maxlen, "‘", "", false);
	ReplaceString(buffer, maxlen, "’", "", false);
	ReplaceString(buffer, maxlen, "[", "", false);
	ReplaceString(buffer, maxlen, "]", "", false);
	ReplaceString(buffer, maxlen, "{", "", false);
	ReplaceString(buffer, maxlen, "}", "", false);
	ReplaceString(buffer, maxlen, "!", "", false);
	ReplaceString(buffer, maxlen, "！", "", false);
	ReplaceString(buffer, maxlen, "¿", "", false);
	ReplaceString(buffer, maxlen, "✵", "", false);
	ReplaceString(buffer, maxlen, "§", "", false);
	ReplaceString(buffer, maxlen, "☆", "", false);
	ReplaceString(buffer, maxlen, "★", "", false);
	ReplaceString(buffer, maxlen, "↑", "", false);
	ReplaceString(buffer, maxlen, "↓", "", false);
	ReplaceString(buffer, maxlen, "←", "", false);
	ReplaceString(buffer, maxlen, "→", "", false);
	ReplaceString(buffer, maxlen, "⋆", "", false);
	ReplaceString(buffer, maxlen, "≛", "", false);
	ReplaceString(buffer, maxlen, "✦", "", false);
	ReplaceString(buffer, maxlen, "✧", "", false);
	ReplaceString(buffer, maxlen, "✩", "", false);
	ReplaceString(buffer, maxlen, "✪", "", false);
	ReplaceString(buffer, maxlen, "✫", "", false);
	ReplaceString(buffer, maxlen, "✬", "", false);
	ReplaceString(buffer, maxlen, "✭", "", false);
	ReplaceString(buffer, maxlen, "✮", "", false);
	ReplaceString(buffer, maxlen, "✯", "", false);
	ReplaceString(buffer, maxlen, "✰", "", false);
	ReplaceString(buffer, maxlen, "⍟", "", false);
	ReplaceString(buffer, maxlen, "⭑", "", false);
	ReplaceString(buffer, maxlen, "⭒", "", false);
	ReplaceString(buffer, maxlen, "⚝", "", false);
	ReplaceString(buffer, maxlen, "⛤", "", false);
	ReplaceString(buffer, maxlen, "✡", "", false);
	ReplaceString(buffer, maxlen, "♡", "", false);
}