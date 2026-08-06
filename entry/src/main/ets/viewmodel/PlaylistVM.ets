import { LocalPlaylist } from 'common'
import { PlaylistManager } from 'hsp_playlist'

/**
 * 歌单 ViewModel — 管理歌单列表的加载和增删
 */
@Observed
export class PlaylistVM {
  playlists: LocalPlaylist[] = []
  private manager: PlaylistManager = PlaylistManager.getInstance()

  async load(): Promise<void> {
    this.playlists = this.manager.getAll()
  }

  async create(name: string, description: string = ''): Promise<LocalPlaylist | null> {
    const pl = await this.manager.create(name, description)
    if (pl) {
      this.playlists = this.manager.getAll()
    }
    return pl
  }

  async delete(id: string): Promise<void> {
    await this.manager.delete(id)
    this.playlists = this.manager.getAll()
  }
}
