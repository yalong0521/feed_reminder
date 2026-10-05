import { FeedSummaryCard } from '../components/FeedSummaryCard';

const storage = new LocalStorage();

@Entry(storage)
@Component
struct FeedNext {
  build() {
    Column() {
      FeedSummaryCard({ dimension: 1 })
    }.width('100%').height('100%')
  }
}
