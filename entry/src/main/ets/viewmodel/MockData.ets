import { ConversationModel, ConversationStatus, IconTheme, TabType } from './ConversationModel'

/**
 * 模拟数据生成器
 */
export class MockDataGenerator {
  /**
   * 生成Claude会话列表数据
   */
  static generateClaudeConversations(): ConversationModel[] {
    const now = new Date()
    return [
      {
        id: '1',
        title: 'React Native项目优化讨论',
        filePath: '/Users/liujie/projects/rn-app',
        messageCount: 78,
        timestamp: new Date(now.getTime() - 34 * 60 * 1000), // 34分钟前
        status: ConversationStatus.SLEEPING,
        iconTheme: IconTheme.BLUE,
        tabType: TabType.CLAUDE
      },
      {
        id: '2',
        title: 'TypeScript类型系统详解',
        filePath: '/Users/liujie/learn/typescript',
        messageCount: 45,
        timestamp: new Date(now.getTime() - 2 * 60 * 60 * 1000), // 2小时前
        status: ConversationStatus.SLEEPING,
        iconTheme: IconTheme.PURPLE,
        tabType: TabType.CLAUDE
      },
      {
        id: '3',
        title: 'GraphQL API设计最佳实践',
        filePath: '/Users/liujie/api/graphql',
        messageCount: 32,
        timestamp: new Date(now.getTime() - 24 * 60 * 60 * 1000), // 昨天
        status: ConversationStatus.ACTIVE,
        iconTheme: IconTheme.ORANGE,
        tabType: TabType.CLAUDE
      },
      {
        id: '4',
        title: 'Node.js性能调优指南',
        filePath: '/Users/liujie/backend/nodejs',
        messageCount: 56,
        timestamp: new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000), // 3天前
        status: ConversationStatus.SLEEPING,
        iconTheme: IconTheme.GREEN,
        tabType: TabType.CLAUDE
      }
    ]
  }

  /**
   * 根据Tab类型获取对应会话列表
   */
  static getConversationsByTab(tabType: TabType): ConversationModel[] {
    switch (tabType) {
      case TabType.CLAUDE:
        return MockDataGenerator.generateClaudeConversations()
      default:
        return []
    }
  }
}
