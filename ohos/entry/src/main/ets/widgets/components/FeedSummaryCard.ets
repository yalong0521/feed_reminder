@Component
export struct FeedSummaryCard {
  // Each form entry supplies its supported dimension explicitly.
  @Prop dimension: number = 3;
  @LocalStorageProp('ready') ready: boolean = false;
  @LocalStorageProp('hasRecords') hasRecords: boolean = false;
  @LocalStorageProp('latestTime') latestTime: string = '暂无记录';
  @LocalStorageProp('latestDate') latestDate: string = '';
  @LocalStorageProp('latestClock') latestClock: string = '暂无记录';
  @LocalStorageProp('latestAmount') latestAmount: string = '记录第一餐';
  @LocalStorageProp('summaryDate') summaryDate: string = '当日汇总';
  @LocalStorageProp('totalAmount') totalAmount: string = '—';
  @LocalStorageProp('feedCount') feedCount: string = '—';
  @LocalStorageProp('nextReminder') nextReminder: string = '打开奶点记后显示记录';
  @LocalStorageProp('updatedAt') updatedAt: string = '数据仅在本机保存';
  @LocalStorageProp('compactReminderLabel') compactReminderLabel: string = '奶点记';
  @LocalStorageProp('compactReminderValue') compactReminderValue: string = '打开应用';

  private open(action: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { feedWidgetAction: action }
    });
  }

  @Builder
  compactCard() {
    // A one-row launcher cell can be only 56vp tall on foldable screens.
    // Reserve the caption, then let the value fit the actual remaining height.
    Column({ space: 2 }) {
      Text(this.compactReminderLabel).fontSize(11).fontColor($r('app.color.widget_secondary'))
        .maxLines(1).minFontSize(9).maxFontSize(11).textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(12).width('100%')
      Text(this.compactReminderValue).fontSize(26).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_primary')).maxLines(1).minFontSize(14).maxFontSize(26)
        .layoutWeight(1).width('100%')
    }
    .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
    .width('100%').height('100%')
    .accessibilityGroup(true)
    .accessibilityText('奶点记，' + this.compactReminderLabel + '，' + this.compactReminderValue + '，' + this.updatedAt)
    .onClick(() => { this.open('open_timer'); })
  }

  @Builder
  squareCard() {
    Column({ space: 6 }) {
      Text('奶点记').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.widget_primary')).width('100%')
        .onClick(() => { this.open('open_timer'); })
      if (this.ready && this.hasRecords) {
        Column({ space: 2 }) {
          Text('最近一餐 · ' + this.latestDate).fontSize(11)
            .fontColor($r('app.color.widget_secondary')).maxLines(1)
          Row({ space: 4 }) {
            Text(this.latestClock).fontSize(28).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.widget_text')).maxLines(1).minFontSize(20).maxFontSize(28)
              .layoutWeight(1)
            Text(this.latestAmount).fontSize(12).fontColor($r('app.color.widget_secondary'))
              .maxLines(2).textAlign(TextAlign.End).constraintSize({ maxWidth: 62 })
          }.width('100%')
        }.alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
        .width('100%').layoutWeight(1)
        .accessibilityGroup(true)
        .accessibilityText('最近一餐，' + this.latestTime + '，' + this.latestAmount + '，' + this.updatedAt)
        .onClick(() => { this.open('open_timer'); })
        Text(this.nextReminder).fontSize(11).fontColor($r('app.color.widget_secondary'))
          .maxLines(1).minFontSize(10).maxFontSize(11).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').onClick(() => { this.open('open_timer'); })
      } else {
        Column({ space: 4 }) {
          Text(this.ready ? '暂无记录' : '喂养记录').fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.widget_text')).maxLines(1).minFontSize(16).maxFontSize(20)
          Text(this.ready ? '记下宝宝的第一餐' : '打开应用后显示记录').fontSize(12)
            .fontColor($r('app.color.widget_secondary')).maxLines(2)
        }.alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
        .width('100%').layoutWeight(1)
        .onClick(() => { this.open('open_timer'); })
      }
      Button(this.ready ? '记录喂奶' : '打开奶点记').fontSize(12)
        .fontColor($r('app.color.widget_on_primary')).backgroundColor($r('app.color.widget_primary'))
        .height(32).width('100%')
        .onClick(() => { this.open(this.ready ? 'record_feed' : 'open_timer'); })
    }.width('100%').height('100%')
  }

  @Builder
  wideCard() {
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
    .width('100%').height('100%')
  }

  build() {
    Column() {
      if (this.dimension === 1) {
        this.compactCard()
      } else if (this.dimension === 2) {
        this.squareCard()
      } else {
        this.wideCard()
      }
    }
    .padding({ left: 12, right: 12, top: this.dimension === 1 ? 6 : 12, bottom: this.dimension === 1 ? 6 : 12 })
    .width('100%').height('100%')
    .backgroundColor($r('app.color.widget_background')).borderRadius(20)
  }
}
