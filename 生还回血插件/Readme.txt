在sm1.12-7210和sm1.11-6970平台均编译成功。
但未在sm1.11-6970平台测试过,
只在sm1.12-7210平台测试过没啥问题.

编译需要依赖 left4dhook v1.159 或以上
链接：https://forums.alliedmods.net/showthread.php?t=321696
链接：https://github.com/SilvDev/Left4DHooks

编译需要依赖 l4d2util 
链接：https://github.com/ConfoglTeam/l4d2util

插件功能很简单,是靠积累对特感的伤害量来转化回血,而非击杀特感来回血.
战役对抗等我想均能兼容.
可设置回实血还是虚血或者两者兼具,
可配置实血虚血分别需要积累多少伤害才触发一次回复,
可配置单次回血量,
可配置根据人数进行插件自动开关接管等等,以及插件调试.

伤害的积累对于特感类型没任何区分,只会区分不同玩家积累的不同伤害值,
说白了这样做不需要纠结特感被抢人头而错失回血.
插件目前我写死了排除tank和witch的伤害积累,
有需要的话根据插件最后的布尔值(bool IsValidSpecialInfected)进行修改等就完事了.

详细的见配置:

// [huixue.smx]
sm_cvar sm_heal_enabled 1           //插件开关,1开0关
sm_cvar sm_heal_h_required 1000     //攻击特感积累多少伤害回一次实血
sm_cvar sm_heal_h_amount 2          //每次回多少实血,设置0则关闭回实血功能
sm_cvar sm_heal_h_max 100           //停止回实血的上限阈值
sm_cvar sm_heal_allow_temp 1        //实血治疗上限阈值里是否应该包含虚血
sm_cvar sm_heal_t_required 600      //攻击特感积累多少血回一次虚血
sm_cvar sm_heal_t_amount 5          //每次回多少虚血,设置0则关闭回虚血功能
sm_cvar sm_heal_t_max 50            //停止回虚血的上限阈值
sm_cvar sm_heal_auto_enabled 0      //是否自动接管回血开关,1是0否
sm_cvar sm_heal_auto_player 2       //少于几人自动接管更改回血开关
sm_cvar sm_heal_melee 1             //近战能否回血
sm_cvar sm_heal_debug 0             //调试开关

管理命令：
!skheal
管理员用于来手动开关插件。
