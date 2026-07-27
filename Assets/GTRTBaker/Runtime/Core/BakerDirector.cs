using System;
using System.Threading;
using UnityEngine;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public static class BakerDirector
    {
        #region ----Public Interfaces----
        public static async Awaitable RunBakeAsync(BaseBaker baker, BakeContext context, CancellationToken token)
        {
            if (!ValidateEnv(context.Settings.EnvMode)) return;

            context.StartTime = Time.realtimeSinceStartup;
            CommandBuffer cmd = null;

            try
            {
                baker.Preprocess(context);//预处理

                cmd = CommandBufferPool.Get(context.Settings.BakeName);
                cmd.Clear();
                baker.Setup(context, cmd);
                Graphics.ExecuteCommandBuffer(cmd);

                while (!context.Settings.StopStrategy.IsFinished(context))
                {
                    token.ThrowIfCancellationRequested();

                    cmd.Clear();
                    baker.BuildStepCommand(context, cmd);
                    Graphics.ExecuteCommandBuffer(cmd);

                    baker.Postprocess(context);
                    context.OnProgress?.Invoke(context.Settings.StopStrategy.GetProgress(context));

                    await Awaitable.NextFrameAsync(token);

#if UNITY_EDITOR
                    UnityEditor.EditorApplication.QueuePlayerLoopUpdate();
#endif
                }
                context.OnCompleted?.Invoke();
            }
            catch (OperationCanceledException) { context.OnCanceled?.Invoke(); }
            catch (Exception e) { context.OnFailed?.Invoke(e); }
            finally
            {
                baker.Dispose();
                if (cmd != null) CommandBufferPool.Release(cmd);
            }
        }
        #endregion

        #region ----Private Interfaces----
        private static bool ValidateEnv(BakeEnvironmentMode mode)
        {
#if UNITY_EDITOR
            if (mode == BakeEnvironmentMode.EditorPlayMode)
                return !Application.isPlaying;
            else 
                return mode == BakeEnvironmentMode.EditorOffline;
#else
            return mode == BakeEnvironmentMode.RuntimeBuild;
#endif
        }
        #endregion
    }
}