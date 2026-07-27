using UnityEngine;

namespace GTRTBaker
{
    public class SppStopStrategy : IBakeStopStrategy
    {
        private readonly int m_targetSPP;
        public SppStopStrategy(int targetSPP)
        {
            m_targetSPP = targetSPP;
        }

        public float GetProgress(BakeContext context)
        {
            return m_targetSPP == 0 ? 0 : (float)context.CurrentSPP / m_targetSPP;
        }

        public bool IsFinished(BakeContext context)
        {
            return context.CurrentSPP >= m_targetSPP;
        }
    }
}