/**
 * 工具名称统一归一化器
 * 所有数据路径的工具名归一化逻辑统一在此，避免散落在多处导致不一致
 */

export class ToolNameNormalizer {
  /**
   * 核心归一化函数：将各种原始工具名映射为统一的标准名称
   * @param name 原始工具名（如 'shell', 'apply_patch', 'mcp_tool_call'）
   * @param content 可选的内容摘要，用于在没有明确工具名时推断类型
   * @returns 标准化的工具名（如 'Bash', 'Edit', 'MCP'）
   */
  static normalize(name: string, content?: string): string {
    const raw = (name || '').trim()
    if (raw.length === 0) return 'Tool'

    // 预处理：去除分隔符用于宽匹配
    const collapsed = raw.replace(/[-_ ]/g, '').toLowerCase()
    const lower = raw.toLowerCase()
    const summary = (content || '').trim().toLowerCase()

    // === shell / unified_exec / execve / command → Bash ===
    if (collapsed === 'shell' || collapsed === 'bash' || collapsed === 'command' ||
      collapsed === 'localcommand' || collapsed === 'unifiedexec' || collapsed === 'execve' ||
      collapsed === 'exec' || collapsed === 'git' || collapsed === 'applescript' ||
      collapsed === 'execcommand' || collapsed === 'shellcommand' || collapsed === 'runcommand' ||
      collapsed === 'terminal') {
      return 'Bash'
    }
    // includes 模糊匹配（在精确匹配之后，避免误杀）
    if (collapsed.includes('exec') || collapsed.includes('terminal') || collapsed.includes('shell')) {
      return 'Bash'
    }

    // === apply_patch / fileChange → Edit ===
    if (collapsed === 'edit' || collapsed === 'fileedit' || collapsed === 'applypatch' ||
      collapsed === 'patch' || collapsed === 'filechange' || collapsed === 'editfile' ||
      collapsed === 'patchfile') {
      return 'Edit'
    }
    if (collapsed.includes('applypatch') || collapsed.includes('patch')) {
      return 'Edit'
    }

    // === write / create_file → Write ===
    if (collapsed === 'write' || collapsed === 'filewrite' || collapsed === 'createfile' ||
      collapsed === 'create' || collapsed === 'savefile' || collapsed === 'writefile') {
      return 'Write'
    }
    if (collapsed.includes('write') && !collapsed.includes('writethread')) {
      return 'Write'
    }

    // === read → Read ===
    if (collapsed === 'read' || collapsed === 'fileread' || collapsed === 'readfile' ||
      collapsed === 'openfile' || collapsed === 'viewfile' || collapsed === 'catfile' ||
      collapsed === 'readthreadterminal') {
      return 'Read'
    }

    // === grep / search → Grep ===
    if (collapsed === 'rg' || collapsed === 'grep' || collapsed === 'search' ||
      collapsed === 'searchfiles' || collapsed === 'textsearch' || collapsed === 'codesearch' ||
      collapsed === 'grepsearch' || collapsed === 'searchcontent' || collapsed === 'ripgrep') {
      return 'Grep'
    }
    if (collapsed.includes('grep') || collapsed.includes('search')) {
      return 'Grep'
    }

    // === glob / list_files → Glob ===
    if (collapsed === 'glob' || collapsed === 'find' || collapsed === 'ls' ||
      collapsed === 'listfiles' || collapsed === 'listdirectory' || collapsed === 'list' ||
      collapsed === 'globsearch' || collapsed === 'findfiles' || collapsed === 'lsfiles' ||
      collapsed === 'locate' || collapsed === 'fd') {
      return 'Glob'
    }
    if (collapsed.includes('glob') || collapsed.includes('find')) {
      return 'Glob'
    }

    // === MCP 工具调用 ===
    if (collapsed === 'mcptoolcall' || collapsed === 'mcp' || collapsed === 'mcptool') {
      return 'MCP'
    }

    // === 网络访问 ===
    if (collapsed === 'networkaccess' || collapsed === 'network') {
      return 'NetworkAccess'
    }

    // === 计算机操控 ===
    if (collapsed === 'computeruse' || collapsed === 'computerusepreview') {
      return 'ComputerUse'
    }

    // === 图像生成 ===
    if (collapsed === 'imagegeneration' || collapsed === 'generateimage' || collapsed === 'imagegen') {
      return 'ImageGeneration'
    }

    // === 权限请求 ===
    if (collapsed === 'requestpermissions' || collapsed === 'permissionrequest') {
      return 'Permission'
    }

    // === 用户输入 ===
    if (collapsed === 'userinput' || collapsed === 'userinputresponse') {
      return 'UserInput'
    }

    // === Web 搜索 ===
    if (collapsed === 'websearch' || collapsed === 'websearchpreview') {
      return 'WebSearch'
    }

    // === Web 抓取 ===
    if (collapsed === 'webfetch' || collapsed === 'fetch') {
      return 'WebFetch'
    }

    // === 加载工作区依赖 ===
    if (collapsed === 'loadworkspacedependencies' || collapsed === 'loaddeps') {
      return 'LoadDeps'
    }

    // === 在 Codex 中打开 ===
    if (collapsed === 'openincodex') {
      return 'OpenInCodex'
    }

    // === Agent ===
    if (collapsed === 'agent' || collapsed === 'collabagent') {
      return 'Agent'
    }

    // === Skill ===
    if (collapsed === 'skill') {
      return 'Skill'
    }

    // === 基于 content 的推断（仅当 name 匹配失败时） ===
    if (content && summary.length > 0) {
      if (summary.startsWith('read ')) return 'Read'
      if (summary.startsWith('search ')) return 'Grep'
      if (summary.startsWith('find ')) return 'Glob'
      if (summary.startsWith('list ')) return 'Glob'
      if (summary.startsWith('review diff')) return 'Bash'
      if (summary.startsWith('check git') || summary.startsWith('run git')) return 'Bash'
      if (summary.startsWith('已编辑') || summary.startsWith('正在编辑')) return 'Edit'
      if (summary.startsWith('run checks')) return 'Bash'
      if (summary.startsWith('check endpoint')) return 'Bash'
      if (summary.startsWith('control codex desktop')) return 'Bash'
      const combined = lower + ' ' + summary
      if (combined.indexOf('bash') >= 0 || combined.indexOf('shell') >= 0 || combined.indexOf('command') >= 0) return 'Bash'
      if (combined.indexOf('edit') >= 0 || combined.indexOf('patch') >= 0 || combined.indexOf('diff') >= 0) return 'Edit'
      if (combined.indexOf('read') >= 0 || combined.indexOf('open') >= 0) return 'Read'
      if (combined.indexOf('grep') >= 0 || combined.indexOf('search') >= 0 || combined.indexOf('rg') >= 0) return 'Grep'
    }

    return raw
  }
}
