using System;
using System.Collections.Generic;
using Unity.Burst;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine;

namespace GTRTBaker
{
    public struct SSRTShadowLightMeshInstance
    {
        public Mesh mesh;
        public Matrix4x4 localToWorld;
        public float[] submeshEmissions;
    }

    [Serializable]
    public struct SSRTShadowGlobalLightTriangle
    {
        public float3 v0;
        public float3 v1;
        public float3 v2;
        public float3 normal;
        public float emissionLuminance;
        public float area;
        public float samplingPMF;
    }

    [Serializable]
    public struct SSRTShadowReservoir
    {
        public uint globalTriangleID;
        public float2 barycentric;
        public float weightSum;
        public uint candidateCount;
        public float targetAtSource;
    }

    [Serializable]
    public struct SSRTShadowAliasEntry
    {
        public float prob;
        public uint aliasIndex;
    }

    public class SSRTShadowLightDataResult : IDisposable
    {
        public NativeArray<SSRTShadowGlobalLightTriangle> triangles;
        public NativeArray<SSRTShadowAliasEntry> aliasTable;
        public int validTriangleCount;

        public void Dispose()
        {
            if (triangles.IsCreated) triangles.Dispose();
            if (aliasTable.IsCreated) aliasTable.Dispose();
        }
    }

    public static class SSRTShadowLightDataBuilder
    {
        public static SSRTShadowLightDataResult Build(List<SSRTShadowLightMeshInstance> instances)
        {
            if (instances == null || instances.Count == 0)
                return new SSRTShadowLightDataResult();

            List<Mesh> meshList = new List<Mesh>(instances.Count);
            NativeArray<float4x4> matrices = new NativeArray<float4x4>(instances.Count, Allocator.TempJob);
            NativeArray<int> submeshEmissionOffsets = new NativeArray<int>(instances.Count, Allocator.TempJob);

            int totalSubmeshCount = 0;
            for (int i = 0; i < instances.Count; i++)
            {
                totalSubmeshCount += instances[i].mesh.subMeshCount;
            }

            NativeArray<float> allSubmeshEmissions = new NativeArray<float>(totalSubmeshCount, Allocator.TempJob);

            int totalMaxTriangles = 0;
            int currentSubmeshOffset = 0;

            for (int i = 0; i < instances.Count; i++)
            {
                var inst = instances[i];
                meshList.Add(inst.mesh);
                matrices[i] = inst.localToWorld;
                submeshEmissionOffsets[i] = currentSubmeshOffset;

                int subCount = inst.mesh.subMeshCount;
                for (int sub = 0; sub < subCount; sub++)
                {
                    float emission = (inst.submeshEmissions != null && sub < inst.submeshEmissions.Length)
                                     ? inst.submeshEmissions[sub] : 0f;

                    allSubmeshEmissions[currentSubmeshOffset + sub] = emission;

                    if (emission > 0f)
                    {
                        totalMaxTriangles += (int)(inst.mesh.GetIndexCount(sub) / 3);
                    }
                }
                currentSubmeshOffset += subCount;
            }

            if (totalMaxTriangles == 0)
            {
                matrices.Dispose();
                submeshEmissionOffsets.Dispose();
                allSubmeshEmissions.Dispose();
                return new SSRTShadowLightDataResult();
            }

            Mesh.MeshDataArray meshDataArray = Mesh.AcquireReadOnlyMeshData(meshList);//@TODO: 这个接口仍然得保证光源网格是可读的, 感觉为了绝对的无资源设置污染, 还是回读合适?

            NativeArray<SSRTShadowGlobalLightTriangle> outTriangles = new NativeArray<SSRTShadowGlobalLightTriangle>(totalMaxTriangles, Allocator.Persistent);
            NativeArray<int> outValidCount = new NativeArray<int>(1, Allocator.TempJob);
            outValidCount[0] = 0;

            var extractJob = new ExtractTrianglesJob
            {
                meshDataArray = meshDataArray,
                localToWorldMatrices = matrices,
                submeshEmissionOffsets = submeshEmissionOffsets,
                allSubmeshEmissions = allSubmeshEmissions,
                outTriangles = outTriangles,
                outValidCount = outValidCount
            };
            JobHandle extractHandle = extractJob.Schedule(instances.Count, 4);

            NativeArray<SSRTShadowAliasEntry> outAliasTable = new NativeArray<SSRTShadowAliasEntry>(totalMaxTriangles, Allocator.Persistent);

            var aliasJob = new BuildAliasTableJob
            {
                triangles = outTriangles,
                aliasTable = outAliasTable,
                validCountRef = outValidCount
            };
            JobHandle aliasHandle = aliasJob.Schedule(extractHandle);

            aliasHandle.Complete();

            meshDataArray.Dispose();
            matrices.Dispose();
            submeshEmissionOffsets.Dispose();
            allSubmeshEmissions.Dispose();

            int finalCount = outValidCount[0];
            outValidCount.Dispose();

            return new SSRTShadowLightDataResult
            {
                triangles = outTriangles,
                aliasTable = outAliasTable,
                validTriangleCount = finalCount
            };
        }

        [BurstCompile(CompileSynchronously = true, FloatMode = FloatMode.Fast, FloatPrecision = FloatPrecision.Standard)]
        private struct ExtractTrianglesJob : IJobParallelFor
        {
            [ReadOnly] public Mesh.MeshDataArray meshDataArray;
            [ReadOnly] public NativeArray<float4x4> localToWorldMatrices;
            [ReadOnly] public NativeArray<int> submeshEmissionOffsets;
            [ReadOnly] public NativeArray<float> allSubmeshEmissions;

            [NativeDisableParallelForRestriction]
            public NativeArray<SSRTShadowGlobalLightTriangle> outTriangles;

            [NativeDisableContainerSafetyRestriction]
            public NativeArray<int> outValidCount;

            public unsafe void Execute(int index)
            {
                Mesh.MeshData data = meshDataArray[index];
                float4x4 l2w = localToWorldMatrices[index];
                int offset = submeshEmissionOffsets[index];

                int vertexCount = data.vertexCount;
                NativeArray<float3> vertices = new NativeArray<float3>(vertexCount, Allocator.Temp);

                data.GetVertices(vertices.Reinterpret<Vector3>());

                for (int sub = 0; sub < data.subMeshCount; sub++)
                {
                    float emission = allSubmeshEmissions[offset + sub];

                    if (emission <= 0f) continue;

                    var indices = new NativeArray<int>(data.GetSubMesh(sub).indexCount, Allocator.Temp);
                    data.GetIndices(indices, sub);

                    for (int t = 0; t < indices.Length; t += 3)
                    {
                        float3 p0 = math.transform(l2w, vertices[indices[t]]);
                        float3 p1 = math.transform(l2w, vertices[indices[t + 1]]);
                        float3 p2 = math.transform(l2w, vertices[indices[t + 2]]);

                        float3 edge1 = p1 - p0;
                        float3 edge2 = p2 - p0;
                        float3 crossProd = math.cross(edge1, edge2);

                        float area = math.length(crossProd) * 0.5f;

                        if (area < 1e-6f) continue;

                        float weight = area * emission;
                        if (weight <= 0f) continue;

                        float3 normal = math.normalize(crossProd / (area * 2f));

                        int* countPtr = (int*)outValidCount.GetUnsafePtr();
                        int outIdx = System.Threading.Interlocked.Add(ref *countPtr, 1) - 1;

                        outTriangles[outIdx] = new SSRTShadowGlobalLightTriangle
                        {
                            v0 = p0,
                            v1 = p1,
                            v2 = p2,
                            normal = normal,
                            emissionLuminance = emission,
                            area = area,
                            samplingPMF = 0f
                        };
                    }
                    indices.Dispose();
                }
                vertices.Dispose();
            }
        }

        [BurstCompile(CompileSynchronously = true)]
        private struct BuildAliasTableJob : IJob
        {
            public NativeArray<SSRTShadowGlobalLightTriangle> triangles;
            public NativeArray<SSRTShadowAliasEntry> aliasTable;
            [ReadOnly] public NativeArray<int> validCountRef;

            public void Execute()
            {
                int validCount = validCountRef[0];
                if (validCount == 0) return;

                double sum = 0.0;
                for (int i = 0; i < validCount; i++)
                {
                    sum += (triangles[i].area * triangles[i].emissionLuminance);
                }

                NativeArray<double> scaledProb = new NativeArray<double>(validCount, Allocator.Temp);
                NativeQueue<int> small = new NativeQueue<int>(Allocator.Temp);
                NativeQueue<int> large = new NativeQueue<int>(Allocator.Temp);

                for (int i = 0; i < validCount; i++)
                {
                    double weight = triangles[i].area * triangles[i].emissionLuminance;
                    float truePdf = (float)(weight / sum);

                    var tri = triangles[i];
                    tri.samplingPMF = truePdf;
                    triangles[i] = tri;

                    scaledProb[i] = truePdf * validCount;

                    if (scaledProb[i] < 1.0)
                        small.Enqueue(i);
                    else
                        large.Enqueue(i);
                }

                while (small.Count > 0 && large.Count > 0)
                {
                    int l = small.Dequeue();
                    int g = large.Dequeue();

                    aliasTable[l] = new SSRTShadowAliasEntry { prob = (float)scaledProb[l], aliasIndex = (uint)g };

                    scaledProb[g] = (scaledProb[g] + scaledProb[l]) - 1.0;

                    if (scaledProb[g] < 1.0)
                        small.Enqueue(g);
                    else
                        large.Enqueue(g);
                }

                while (large.Count > 0)
                {
                    int g = large.Dequeue();
                    aliasTable[g] = new SSRTShadowAliasEntry { prob = 1.0f, aliasIndex = (uint)g };
                }

                while (small.Count > 0)
                {
                    int l = small.Dequeue();
                    aliasTable[l] = new SSRTShadowAliasEntry { prob = 1.0f, aliasIndex = (uint)l };
                }

                scaledProb.Dispose();
                small.Dispose();
                large.Dispose();
            }
        }
    }
}