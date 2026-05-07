import { MessageModel, MessageType, ToolStatus, ToolType } from './MessageModel'

/**
 * 模拟消息数据生成器
 */
export class MockMessageData {
  /**
   * 生成对话消息列表
   */
  static generateMessages(): MessageModel[] {
    return [
      {
        id: '1',
        type: MessageType.TEXT,
        content: '我来帮你创建这个项目。首先让我检查一下项目结构，然后创建必要的文件和组件。',
        timestamp: '10:30',
        isUser: false
      },
      {
        id: '2',
        type: MessageType.TOOL_EXECUTION,
        content: '查看项目目录结构',
        timestamp: '10:30',
        isUser: false,
        toolInfo: {
          toolType: ToolType.SHELL,
          toolName: 'SHELL',
          status: ToolStatus.SUCCESS,
          icon: $r('app.media.ic_tool_shell')
        }
      },
      {
        id: '3',
        type: MessageType.TEXT,
        content: '项目目录已创建完成。现在我将创建主要的组件文件，包括主题配置、数据模型和UI组件。',
        timestamp: '10:31',
        isUser: false
      },
      {
        id: '4',
        type: MessageType.TOOL_EXECUTION,
        content: '创建主题配置文件',
        timestamp: '10:31',
        isUser: false,
        toolInfo: {
          toolType: ToolType.WRITE_FILE,
          toolName: 'WRITE_FILE',
          status: ToolStatus.SUCCESS,
          icon: $r('app.media.ic_tool_file')
        }
      },
      {
        id: '5',
        type: MessageType.TOOL_EXECUTION,
        content: '创建数据模型',
        timestamp: '10:32',
        isUser: false,
        toolInfo: {
          toolType: ToolType.UPDATE_PLAN,
          toolName: 'UPDATE_PLAN',
          status: ToolStatus.SUCCESS,
          icon: $r('app.media.ic_tool_plan')
        }
      },
      {
        id: '6',
        type: MessageType.EXECUTING,
        content: '执行中',
        timestamp: '10:33',
        isUser: false,
        executingInfo: {
          command: 'npm install',
          duration: 2
        }
      },
      {
        id: '7',
        type: MessageType.TEXT,
        content: '项目基础结构已创建完成。接下来我将创建主要的页面组件，包括会话列表页面和主页面框架。',
        timestamp: '10:35',
        isUser: false
      }
    ]
  }
}
