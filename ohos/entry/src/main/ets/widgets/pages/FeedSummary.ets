const storage = new LocalStorage();

@Entry(storage)
@Component
struct FeedSummary {
  @LocalStorageProp('ready') ready: boolean = false;
  @LocalStorageProp('hasRecords') hasRecords: boolean = false;
  @LocalStorageProp('latestTime') latestTime: string = '暂无记录';
  @LocalStorageProp('latestAmount') latestAmount: string = '记录第一餐';
  @LocalStorageProp('summaryDate') summaryDate: string = '当日汇总';
  @LocalStorageProp('totalAmount') totalAmount: string = '—';
  @LocalStorageProp('feedCount') feedCount: string = '—';
  @LocalStorageProp('nextReminder') nextReminder: string = '打开奶点记后显示记录';
  @LocalStorageProp('updatedAt') updatedAt: string = '数据仅在本机保存';

  private open(action: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { feedWidgetAction: action }
    });
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('奶点记').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.widget_primary'))
        Blank()
        Text(this.ready ? this.summaryDate : '喂养记录').fontSize(11).fontColor($r('app.color.widget_secondary'))
      }.width('100%').onClick(() => { this.open('open_timer'); })
      if (this.ready) {
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text('最近一餐').fontSize(11).fontColor($r('app.color.widget_secondary'))
            Text(this.latestTime).fontSize(20).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.widget_text')).maxLines(1).minFontSize(15).maxFontSize(20)
            Text(this.latestAmount).fontSize(13).fontColor($r('app.color.widget_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Column({ space: 4 }) {
            Text(this.totalAmount).fontSize(22).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.widget_primary')).maxLines(1).minFontSize(16).maxFontSize(22)
            Text(this.feedCount).fontSize(13).fontColor($r('app.color.widget_secondary'))
          }.alignItems(HorizontalAlign.End).layoutWeight(1)
        }.width('100%').layoutWeight(1).onClick(() => { this.open('open_timer'); })
        Row({ space: 8 }) {
          Text(this.nextReminder).fontSize(12).fontColor($r('app.color.widget_text'))
            .maxLines(2).layoutWeight(1)
            .onClick(() => { this.open('open_timer'); })
          Button('记录喂奶').fontSize(12).fontColor($r('app.color.widget_on_primary'))
            .backgroundColor($r('app.color.widget_primary')).height(32)
            .onClick(() => { this.open('record_feed'); })
        }.width('100%')
      } else {
        Text('打开奶点记后显示记录').fontSize(16).fontColor($r('app.color.widget_text'))
          .layoutWeight(1).width('100%').textAlign(TextAlign.Start)
          .onClick(() => { this.open('open_timer'); })
        Button('打开奶点记').fontSize(13).fontColor($r('app.color.widget_on_primary'))
          .backgroundColor($r('app.color.widget_primary')).height(32).width('100%')
          .onClick(() => { this.open('open_timer'); })
      }
      Text(this.updatedAt).fontSize(10).fontColor($r('app.color.widget_secondary'))
        .maxLines(1).width('100%').textAlign(TextAlign.Start)
        .onClick(() => { this.open('open_timer'); })
    }
    .padding(12).width('100%').height('100%')
    .backgroundColor($r('app.color.widget_background')).borderRadius(20)
  }
}
