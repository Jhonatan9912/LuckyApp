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
        """Promueve comisiones pending → available según event_time."""
        with app.app_context():
            updated = mature_commissions(minutes=minutes, days=days)
            click.echo(f"MATURE COMMISSIONS updated: {updated}")
