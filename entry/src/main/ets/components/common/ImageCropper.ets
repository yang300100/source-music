import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { LogUtils } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 图片裁剪弹窗（全屏）
 *
 * 显示选中的图片，提供裁剪框（支持拖拽平移、双指缩放），
 * 确认后按裁剪框区域裁切并保存到应用沙箱，回调通知外部。
 */
@CustomDialog
export struct ImageCropper {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 对话框控制器（@CustomDialog 必需） */
  controller: CustomDialogController
  /** 待裁剪图片 URI（PhotoViewPicker 返回） */
  @Prop srcUri: string = ''
  /** 裁剪完成回调（参数为保存后的沙箱文件路径） */
  onCropDone: (filePath: string) => void = (filePath: string) => {}
  /** 裁剪框相对图片的比例（宽/高，如 1 = 正方形，16/9 ≈ 1.78） */
  @Prop frameRatio: number = 1.0

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  /** 原始图片 PixelMap 与尺寸 */
  private srcPixelMap: image.PixelMap | null = null
  private srcWidth: number = 0
  private srcHeight: number = 0
  /** 图片显示区尺寸（vp） */
  private viewWidth: number = 0
  private viewHeight: number = 0
  /** 图片在显示区的位置与缩放（vp 坐标系） */
  private imgOffsetX: number = 0
  private imgOffsetY: number = 0
  private imgScale: number = 1.0
  /** 手势状态 */
  private dragStartX: number = 0
  private dragStartY: number = 0
  private dragBaseX: number = 0
  private dragBaseY: number = 0
  private pinchBaseScale: number = 1.0
  /** 裁剪框大小（vp，居中显示） */
  private frameW: number = 260
  private frameH: number = 260
  @State entered: boolean = false

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }

  aboutToAppear(): void {
    this.frameH = this.frameW / this.frameRatio
    this.loadSource()
    setTimeout(() => { this.entered = true }, 20)
  }

  /** 加载源图片 */
  private async loadSource(): Promise<void> {
    let fd: fileIo.File | null = null
    try {
      LogUtils.info(`[裁剪] 加载图片: ${this.srcUri}`)
      // PhotoViewPicker 返回 file://media/... uri：先 open 获取 fd，再创建 ImageSource
      fd = fileIo.openSync(this.srcUri, fileIo.OpenMode.READ_ONLY)
      const source = image.createImageSource(fd.fd)
      const pixelMap = await source.createPixelMap()
      source.release()
      fileIo.closeSync(fd)
      fd = null
      this.srcPixelMap = pixelMap
      this.srcWidth = pixelMap.getImageInfoSync().size.width
      this.srcHeight = pixelMap.getImageInfoSync().size.height
      LogUtils.info(`[裁剪] 图片加载成功: ${this.srcWidth}x${this.srcHeight}`)
      // 若显示区已就绪则绘制（onAreaChange 可能先于 loadSource 触发）
      if (this.viewWidth > 0 && this.viewHeight > 0) {
        this.calcFit()
      }
    } catch (err) {
      if (fd) {
        try {
          fileIo.closeSync(fd)
        } catch (e) {}
      }
      LogUtils.error(`[裁剪] 加载图片失败: ${JSON.stringify(err)}`)
    }
  }

  /** 计算图片适配显示区的缩放与偏移（contain） */
  private calcFit(): void {
    if (this.viewWidth <= 0 || this.viewHeight <= 0 || this.srcWidth <= 0) {
      LogUtils.info(`[裁剪] calcFit 尺寸未就绪: view=${this.viewWidth}x${this.viewHeight}, src=${this.srcWidth}x${this.srcHeight}`)
      return
    }
    const scaleX = this.viewWidth / this.srcWidth
    const scaleY = this.viewHeight / this.srcHeight
    this.imgScale = Math.min(scaleX, scaleY)
    this.imgOffsetX = (this.viewWidth - this.srcWidth * this.imgScale) / 2
    this.imgOffsetY = (this.viewHeight - this.srcHeight * this.imgScale) / 2
    LogUtils.info(`[裁剪] calcFit: scale=${this.imgScale}, offset=(${this.imgOffsetX}, ${this.imgOffsetY})`)
    this.draw()
  }

  /** 绘制裁剪界面：图片 + 暗色遮罩 + 裁剪框 */
  private draw(): void {
    const ctx = this.ctx
    ctx.clearRect(0, 0, this.viewWidth, this.viewHeight)
    // 绘制图片
    if (this.srcPixelMap) {
      ctx.drawImage(this.srcPixelMap, this.imgOffsetX, this.imgOffsetY, this.srcWidth * this.imgScale, this.srcHeight * this.imgScale)
    }
    // 遮罩：框外变暗
    const fw = this.frameW
    const fh = this.frameH
    const fx = (this.viewWidth - fw) / 2
    const fy = (this.viewHeight - fh) / 2
    ctx.fillStyle = 'rgba(0,0,0,0.55)'
    // 上
    ctx.fillRect(0, 0, this.viewWidth, fy)
    // 下
    ctx.fillRect(0, fy + fh, this.viewWidth, this.viewHeight - fy - fh)
    // 左
    ctx.fillRect(0, fy, fx, fh)
    // 右
    ctx.fillRect(fx + fw, fy, this.viewWidth - fx - fw, fh)
    // 裁剪框边框
    ctx.strokeStyle = '#ffffff'
    ctx.lineWidth = 2
    ctx.strokeRect(fx, fy, fw, fh)
    // 四角标记
    ctx.fillStyle = '#b388ff'
    ctx.fillRect(fx - 2, fy - 2, 12, 4)
    ctx.fillRect(fx - 2, fy - 2, 4, 12)
    ctx.fillRect(fx + fw - 10, fy - 2, 12, 4)
    ctx.fillRect(fx + fw - 2, fy - 2, 4, 12)
    ctx.fillRect(fx - 2, fy + fh - 2, 12, 4)
    ctx.fillRect(fx - 2, fy + fh - 10, 4, 12)
    ctx.fillRect(fx + fw - 10, fy + fh - 2, 12, 4)
    ctx.fillRect(fx + fw - 2, fy + fh - 10, 4, 12)
  }

  /** 执行裁剪并保存 */
  private async doCrop(): Promise<void> {
    try {
      const pixelMap = this.srcPixelMap
      if (!pixelMap) return
      const fw = this.frameW
      const fh = this.frameH
      const fx = (this.viewWidth - fw) / 2
      const fy = (this.viewHeight - fh) / 2
      // 将裁剪框区域映射到原始图片像素坐标
      const srcX = (fx - this.imgOffsetX) / (this.srcWidth * this.imgScale) * this.srcWidth
      const srcY = (fy - this.imgOffsetY) / (this.srcHeight * this.imgScale) * this.srcHeight
      const srcW = fw / (this.srcWidth * this.imgScale) * this.srcWidth
      const srcH = fh / (this.srcHeight * this.imgScale) * this.srcHeight
      // 裁剪（限制在图片范围内）
      const clampX = Math.max(0, Math.min(srcX, this.srcWidth - 1))
      const clampY = Math.max(0, Math.min(srcY, this.srcHeight - 1))
      const clampW = Math.max(1, Math.min(srcW, this.srcWidth - clampX))
      const clampH = Math.max(1, Math.min(srcH, this.srcHeight - clampY))
      // 原地裁剪到裁剪框区域（cropSync 修改原 PixelMap）
      const region: image.Region = {
        x: Math.round(clampX),
        y: Math.round(clampY),
        size: {
          width: Math.round(clampW),
          height: Math.round(clampH)
        }
      }
      pixelMap.cropSync(region)
      // 使用 ImagePacker 编码保存到沙箱（packToFile 需文件描述符）
      const context = getContext(this)
      const filePath = `${context.filesDir}/custom_bg.jpg`
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      const packer = image.createImagePacker()
      const packingOption: image.PackingOption = {
        format: 'image/jpeg',
        quality: 92
      }
      await packer.packToFile(pixelMap, fd.fd, packingOption)
      fileIo.closeSync(fd)
      packer.release()
      pixelMap.release()
      this.onCropDone(filePath)
      this.controller?.close()
    } catch (err) {
      LogUtils.error(`[裁剪] 裁剪失败: ${JSON.stringify(err)}`)
    }
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('取消')
          .fontSize(15).fontColor(this.secondaryText)
          .padding(12)
          .onClick(() => { this.controller?.close() })
        Blank()
        Text('裁剪图片')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        Blank()
        Text('确定')
          .fontSize(15).fontColor(this.accentColor)
          .padding(12)
          .onClick(() => { this.doCrop() })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 裁剪画布
      Stack() {
        Canvas(this.ctx)
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            void oldValue
            const w = Number(newValue.width)
            const h = Number(newValue.height)
            if (w > 0 && h > 0 && (w !== this.viewWidth || h !== this.viewHeight)) {
              this.viewWidth = w
              this.viewHeight = h
              this.calcFit()
            }
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PanGesture()
                .onActionStart(() => {
                  this.dragStartX = this.imgOffsetX
                  this.dragStartY = this.imgOffsetY
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.imgOffsetX = this.dragStartX + event.offsetX
                  this.imgOffsetY = this.dragStartY + event.offsetY
                  this.draw()
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.pinchBaseScale = this.imgScale
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (event.scale > 0) {
                    this.imgScale = this.pinchBaseScale * event.scale
                    this.draw()
                  }
                })
            )
          )
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.Black)

      // 底部提示
      Text('拖动图片调整位置，双指缩放')
        .fontSize(12).fontColor(this.secondaryText)
        .padding(16)
    }
    .width('100%').height('100%')
    .backgroundColor(this.isDark ? '#14121a' : '#f2f0f6')
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.98, y: this.entered ? 1 : 0.98 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }
}
