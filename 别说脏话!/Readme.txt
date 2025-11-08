目前插件只在sm1.12-7210下测试没问题,
sm1.11-6970未测试,但我想应该也没啥问题.
如果发现bug,发iss里即可.

插件使用上,初次加载插件后,会在:
addons/sourcemod/data文件夹里生成一个叫BieShuoZangHua.txt的文件,
具体敏感词在此txt文件内配置即可,文件内也已写了注释,可根据需要按葫芦画瓢.
//[和谐规则配置]
; [!]检测上,会自动转化小写再去除特殊符号,最后再用于检测,因此使用小写即可.
; [!]配置可用双斜杠(//)或分号(;)来进行注释.
//配置格式:
;       被检测字词_替换字词_替换模式
//替换模式:
;       1=只替换相应字词.
;       2=满足全部被检测字词则直接替换整句,多个被检测字词之间可用逗号(,)分隔.
//例：
nt_Nice Try!!_1
gg_Good Game!!_1
fuck_杂鱼♡~_2
sb_杂鱼♡~_1
傻,逼_杂鱼♡_2

注:
为了使得!或/开头的聊天命令可以正常使用不被篡改,因此只能移除消息前的空格后其允许正常输出.
因此非常建议使用sir please的bequiet插件屏蔽命令在聊天框的输出↓↓↓
bequiet插件源码：
https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/bequiet.sp
翻译文件：
https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/translations/bequiet.phrases.txt

管理员命令：
!bszh_reload    //重载规则配置

ConVars:
sm_bszh_enabled          //插件开关.(1开,0关.)
sm_bszh_admin_immunity   //是否开启管理员检测豁免?(1是,0否.)
sm_bszh_debug            //调试开关.(1开,0关.)

最后，星云猫猫提醒您，文明聊天，你我做起。
