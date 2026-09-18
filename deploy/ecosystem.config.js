// pm2 进程守护配置 —— 机械臂的 Node 服务
//
// 用法：
//   pm2 start deploy/ecosystem.config.js
//   pm2 save                     # 保存进程列表
//   pm2 startup                  # 生成开机自启脚本（按提示执行输出的那行命令）
//
// 常用命令：
//   pm2 list          查看状态
//   pm2 logs robot-arm   看日志
//   pm2 restart robot-arm
//   pm2 reload robot-arm  零停机重启

module.exports = {
  apps: [
    {
      name: 'robot-arm',
      cwd: '/opt/robot-arm/robot-arm2/server',
      script: 'server.js',

      // 单实例 —— WebSocket 连接状态存在进程内存里，
      // 多实例会导致 ESP32 连到 A 实例、命令发到 B 实例，所以不能用 cluster 模式
      instances: 1,
      exec_mode: 'fork',

      // 崩溃自动重启
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,

      // 内存超限自动重启（2G 小机器上防内存泄漏拖垮系统）
      max_memory_restart: '400M',

      // ⚠️ 这里**故意不设置** ADMIN_PASSWORD / ESP32_TOKEN / DB_PASSWORD
      //
      //    原因：server/config.js 读配置的写法是
      //        process.env.ADMIN_PASSWORD || '默认值'
      //    环境变量**优先**。如果在这里写了占位值，就会盖掉 config.js
      //    里的真实密码，导致数据库连接失败、服务起不来。
      //
      //    密码统一由服务器上的 config.js 提供（该文件不进 Git、
      //    也不会被 rsync 覆盖，见 deploy/push.sh 的排除规则）。
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
      },

      // 日志
      error_file: '/var/log/pm2/robot-arm-error.log',
      out_file: '/var/log/pm2/robot-arm-out.log',
      merge_logs: true,
      time: true,
    },
  ],
};
