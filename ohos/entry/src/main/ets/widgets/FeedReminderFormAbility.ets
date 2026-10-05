import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { WidgetStore, WidgetViewData } from './WidgetStore';

export default class FeedReminderFormAbility extends FormExtensionAbility {
  private static changes: Promise<void> = Promise.resolve();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    // No business data is read before an app-generated, consented snapshot
    // exists. Always return a private placeholder for the first synchronous frame.
    if (typeof id === 'string' && id.length > 0) {
      this.changeInstance(id, false);
    }
    return formBindingData.createFormBindingData(new WidgetViewData());
  }

  onUpdateForm(formId: string): void {
    // Also repairs the instance index if the system restores an existing card.
    this.changeInstance(formId, false);
  }

  onCastToNormalForm(formId: string): void {
    this.changeInstance(formId, false);
  }

  onRemoveForm(formId: string): void {
    this.changeInstance(formId, true);
  }

  private changeInstance(id: string, remove: boolean): void {
    FeedReminderFormAbility.changes = FeedReminderFormAbility.changes.then(async () => {
      try {
        await WidgetStore.changeForm(this.context, id, remove);
      } catch (_) {
        // A full disk can prevent index repair without preventing an existing
        // card from reading the last committed app projection.
        console.warn('Widget instance index unavailable');
      }
      if (!remove) await this.refresh(id);
    }).catch(() => {
      console.warn('Widget instance update unavailable');
    });
  }

  private async refresh(id: string): Promise<void> {
    try {
      let data = await WidgetStore.readSnapshot(this.context);
      while (true) {
        await formProvider.updateForm(id, formBindingData.createFormBindingData(data));
        // The app publishes from a different process. An older lifecycle read
        // can finish updateForm after that newer app update. Re-read after the
        // asynchronous write and converge before releasing this refresh.
        const latest = await WidgetStore.readSnapshot(this.context);
        if (JSON.stringify(latest) === JSON.stringify(data)) return;
        data = latest;
      }
    } catch (_) {
      // Keep the last rendered snapshot and its explicit date/time on failure.
      console.warn('Widget refresh unavailable');
    }
  }
}
