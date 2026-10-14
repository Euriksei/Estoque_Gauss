export default function Carregando() {
  return (
    <div className="animate-pulse space-y-4" aria-busy="true" aria-label="Carregando">
      <div className="h-6 w-40 rounded bg-slate-200" />
      <div className="h-10 w-full rounded-lg bg-slate-200" />
      <div className="h-64 w-full rounded-xl bg-slate-200" />
    </div>
  );
}
