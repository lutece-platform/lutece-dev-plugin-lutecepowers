// Schéma du graphe de fonctionnalités (Phase 2 — détection centrale).
export type NodeType = 'view' | 'action' | 'form' | 'list-control' | 'entity';
export type EdgeKind = 'navigue-vers' | 'declenche' | 'rend' | 'opere-sur';

export interface GraphNode {
  id: string;
  type: NodeType;
  label: string;
  source: string;
  meta?: Record<string, string>;
}

export interface GraphEdge {
  from: string;
  to: string;
  kind: EdgeKind;
}

export interface FeatureGraph {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

/** Fusionne plusieurs sous-graphes : dédup des nœuds par id, des arêtes par (from|kind|to). */
export function mergeGraphs(gs: FeatureGraph[]): FeatureGraph {
  const nodes = new Map<string, GraphNode>();
  const edges = new Map<string, GraphEdge>();
  for (const g of gs) {
    for (const n of g.nodes) nodes.set(n.id, { ...nodes.get(n.id), ...n });
    for (const e of g.edges) edges.set(`${e.from}|${e.kind}|${e.to}`, e);
  }
  return { nodes: [...nodes.values()], edges: [...edges.values()] };
}
