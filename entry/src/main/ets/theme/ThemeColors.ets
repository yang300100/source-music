/**
 * 全局主题颜色工具
 *
 * 统一各页面/组件中重复定义的主题色 getter。
 * 注意：部分同名颜色在不同组件中透明度/亮度不同（如 cardBg），
 * 为保证重构前后外观完全一致，按组件用途细分命名，颜色值严格照搬原实现。
 */
export class ThemeColors {
  /** 主文本色（各页面一致） */
  static primaryText(isDark: boolean): ResourceColor {
    return isDark ? '#e8e0f8' : '#1a1525'
  }

  /** 次级文本色（各页面一致） */
  static secondaryText(isDark: boolean): ResourceColor {
    return isDark ? '#7a6f98' : '#6b6088'
  }

  /** 弱化文本色（歌曲条目/播放页） */
  static dimText(isDark: boolean): ResourceColor {
    return isDark ? '#a090c0' : '#7a6f98'
  }

  /** 强调色（固定） */
  static accentColor(): ResourceColor {
    return '#b388ff'
  }

  /** 页面卡片边框（Settings/Playlist/Search 等） */
  static borderFaint(isDark: boolean): ResourceColor {
    return isDark ? '#08ffffff' : '#08000000'
  }

  /** 导航胶囊/迷你播放条边框（Index 用，透明度略高） */
  static navBorderFaint(isDark: boolean): ResourceColor {
    return isDark ? '#10ffffff' : '#08000000'
  }

  /** 弹窗边框 */
  static dialogBorderFaint(isDark: boolean): ResourceColor {
    return isDark ? '#15ffffff' : '#10000000'
  }

  /** 标准卡片背景（Settings/PlaylistList/PlaylistDetail/SourceManage） */
  static cardBg(isDark: boolean): ResourceColor {
    return isDark ? '#50181525' : '#c0ffffff'
  }

  /** 歌曲条目卡片背景（MusicItemView） */
  static musicCardBg(isDark: boolean): ResourceColor {
    return isDark ? '#30181525' : '#90ffffff'
  }

  /** 播放页封面/信息区背景（NowPlaying PlayerSection） */
  static playerCardBg(isDark: boolean): ResourceColor {
    return isDark ? '#80181525' : '#c0ffffff'
  }

  /** 播放页进度条面板背景 */
  static panelBg(isDark: boolean): ResourceColor {
    return isDark ? '#50141220' : '#b0ffffff'
  }

  /** 播放页毛玻璃面板背景（播放列表/歌词区） */
  static glassBg(isDark: boolean): ResourceColor {
    return isDark ? '#40141220' : '#a0ffffff'
  }

  /** 歌单侧栏背景 */
  static sidebarBg(isDark: boolean): ResourceColor {
    return isDark ? '#50181525' : '#a0ffffff'
  }

  /** 搜索输入框背景（SearchPage） */
  static inputBg(isDark: boolean): ResourceColor {
    return isDark ? '#60181525' : '#c0ffffff'
  }

  /** 弹窗输入框背景（PlaylistNameDialog） */
  static dialogInputBg(isDark: boolean): ResourceColor {
    return isDark ? '#80181525' : '#c0e8e0f0'
  }

  /** 搜索源 chip 背景（SearchPage） */
  static chipBg(isDark: boolean): ResourceColor {
    return isDark ? '#60181525' : '#c0e8e0f0'
  }

  /** 歌曲封面占位背景（MusicItemView） */
  static placeholderBg(isDark: boolean): ResourceColor {
    return isDark ? '#60181525' : '#60e0d8ea'
  }

  /** 弹窗背景（PlaylistNameDialog） */
  static dialogBg(isDark: boolean): ResourceColor {
    return isDark ? '#90181525' : '#e0ffffff'
  }

  /** 悬浮胶囊背景（Index NavCapsule） */
  static capsuleBg(isDark: boolean): ResourceColor {
    return isDark ? '#e81e1a30' : '#d0ffffff'
  }

  /** 迷你播放条背景（Index MiniPlayerBar） */
  static barBg(isDark: boolean): ResourceColor {
    return isDark ? '#e0181525' : '#a0ffffff'
  }

  /** 迷你播放条发光色（仅深色） */
  static barGlowColor(isDark: boolean): ResourceColor {
    return isDark ? '#80e060d0' : '#00000000'
  }

  /** 胶囊选中项背景（Index NavCapsule） */
  static activeBg(isDark: boolean): ResourceColor {
    return isDark ? '#30b388ff' : '#20b388ff'
  }

  /** 歌单侧栏选中项背景（PlaylistListPage） */
  static playlistActiveBg(isDark: boolean): ResourceColor {
    return isDark ? '#18b388ff' : '#15b388ff'
  }

  /** 歌词无内容提示色（LyricView） */
  static noLyricColor(isDark: boolean): ResourceColor {
    return isDark ? '#7a6f98' : '#6b6088'
  }

  /** 歌词普通行色（LyricView） */
  static dimLyricColor(isDark: boolean): ResourceColor {
    return isDark ? '#4a4260' : '#9088a0'
  }

  /** 歌词翻译行色（LyricView） */
  static transLyricColor(isDark: boolean): ResourceColor {
    return isDark ? '#3a3450' : '#a098b0'
  }
}
