export interface Run {
  id: string;
  name: string;
  status: 'pending' | 'running' | 'complete' | 'failed';
}

export function searchRuns(query: string, runs: Run[]): Run[] {
  if (!query) return runs;
  const q = query.toLowerCase();
  return runs.filter(r => r.name.toLowerCase().includes(q));
}
