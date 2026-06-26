# app/cli.py
import click
from app.services.referrals.payouts_service import mature_commissions

def register_cli(app):
    @app.cli.command("mature-commissions")
    @click.option("--minutes", type=int, default=None,
                  help="Override de ventana en minutos (QA/Staging). Si se setea, ignora --days.")
    @click.option("--days", type=int, default=None,
                  help="Ventana en días (Producción).")
    def mature_commissions_cmd(minutes, days):
        """Promueve comisiones pending → available según event_time.
        También expira suscripciones vencidas (corre cada 5 min vía Railway cron)."""
        with app.app_context():
            # Expirar suscripciones vencidas en cada ejecución del cron
            try:
                from app.subscriptions.service import expire_all_stale
                expired = expire_all_stale()
                if expired:
                    click.echo(f"EXPIRE STALE SUBS: {expired} suscripciones expiradas")
            except Exception as e:
                click.echo(f"EXPIRE STALE SUBS error: {e}", err=True)

            updated = mature_commissions(minutes=minutes, days=days)
            click.echo(f"MATURE COMMISSIONS updated: {updated}")
