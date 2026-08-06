import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { LogUtils } from './LogUtils'

const STORE_NAME = 'lx_music_store'

/**
 * 本地持久化存储封装，基于 preferences
 */
export class StorageUtils {
  private static store: preferences.Preferences | null = null

  static async init(context: Context): Promise<void> {
    try {
      StorageUtils.store = await preferences.getPreferences(context, STORE_NAME)
      LogUtils.info('存储初始化成功')
    } catch (err) {
      LogUtils.error('存储初始化失败', JSON.stringify(err))
    }
  }

  static async putString(key: string, value: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.put(key, value)
    await StorageUtils.store.flush()
  }

  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!StorageUtils.store) return defaultValue
    return await StorageUtils.store.get(key, defaultValue) as string
  }

  static async putObject(key: string, value: Object): Promise<void> {
    await StorageUtils.putString(key, JSON.stringify(value))
  }

  static async getObject<T>(key: string, defaultValue: T): Promise<T> {
    const str = await StorageUtils.getString(key, '')
    if (!str) return defaultValue
    try {
      return JSON.parse(str) as T
    } catch {
      return defaultValue
    }
  }

  static async delete(key: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.delete(key)
    await StorageUtils.store.flush()
  }
}
