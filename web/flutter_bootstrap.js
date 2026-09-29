{{flutter_js}}
{{flutter_build_config}}

function reportStartupError(error) {
  console.error('Unable to start 奶点记:', error);
  window.dispatchEvent(new Event('feed-reminder-startup-error'));
}

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (error) {
      reportStartupError(error);
    }
  },
}).catch(reportStartupError);
