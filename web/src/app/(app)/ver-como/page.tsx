import { getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { VerComoForm } from "@/components/VerComo";

export const dynamic = "force-dynamic";

// "Ver como": só para quem é administrador de verdade (perfil_real), mesmo enquanto simula outro perfil.
export default async function VerComo() {
  const usuario = (await getUsuario())!;
  const real = usuario.visao?.perfil_real ?? usuario.perfil;
  if (real !== "admin") return <p className="text-sm">Somente administradores.</p>;
  const [{ todos }, tecnicos] = await Promise.all([getLocais(usuario), getTecnicos()]);
  const carros = new Map(todos.filter((l) => l.tipo === "tecnico" && l.tecnico_id).map((l) => [l.tecnico_id!, l.nome]));
  return (
    <div className="space-y-3">
      <h1 className="text-xl font-bold text-marinho-900">Ver como outro perfil</h1>
      <p className="text-sm text-slate-600">Veja o sistema com os menus, as telas e as permissões de outro perfil, para conferir o que cada pessoa enxerga e pode fazer.</p>
      <VerComoForm estoques={todos.filter((l) => l.tipo === "estoque").map((l) => ({ id: l.id, nome: l.nome }))}
        tecnicos={tecnicos.filter((t) => t.ativo && carros.has(t.id)).map((t) => ({ ...t, carro: carros.get(t.id)! }))}
        atual={{ perfil: usuario.perfil, local_id: usuario.visao?.local_id ?? null, tecnico_id: usuario.visao?.tecnico_id ?? null }} />
    </div>
  );
}
