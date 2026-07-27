using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace GTRTBaker
{
    public abstract class BaseBaker : IDisposable
    {
        public abstract void Preprocess(BakeContext context);
        public abstract void Setup(BakeContext context, CommandBuffer cmd);
        public abstract void BuildStepCommand(BakeContext context, CommandBuffer cmd);
        public abstract void Postprocess(BakeContext context);
        public abstract void Dispose();
    }
}