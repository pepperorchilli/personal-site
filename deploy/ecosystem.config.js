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

      env: {
        NODE_ENV: 'production',
        PORT: 3000,

        // ⚠️ 下面三项必须改成你自己的值
        //    也可以用 pm2 的 --update-env 配合系统环境变量覆盖
        ADMIN_PASSWORD: 'CHANGE_ME_管理员密码',
        ESP32_TOKEN: 'CHANGE_ME_ESP32暗号',
        DB_PASSWORD: 'CHANGE_ME_数据库密码',

        DB_HOST: '127.0.0.1',
        DB_PORT: 3306,
        DB_USER: 'arm_app',
        DB_NAME: 'robot_arm',
      },

      // 日志
      error_file: '/var/log/pm2/robot-arm-error.log',
      out_file: '/var/log/pm2/robot-arm-out.log',
      merge_logs: true,
      time: true,
    },
  ],
};
