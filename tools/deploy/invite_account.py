#!/usr/bin/env python3
"""Issue or revoke a tester invitation using the gateway's private auth database."""
import argparse
import getpass
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from server.account_auth import AccountAuth


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--database',type=Path,required=True)
    p.add_argument('--uses',type=int,default=1); p.add_argument('--hours',type=int,default=168)
    p.add_argument('--revoke',action='store_true',help='Read the code privately from the terminal and revoke it')
    args=p.parse_args()
    if not args.database.is_file(): p.error('Use the existing gateway auth database; refusing to create a different database')
    auth=AccountAuth(args.database)
    if args.revoke:
        auth.revoke_invite(getpass.getpass('Invitation to revoke: ')); print('Invitation revoked.')
    else:
        print(auth.issue_invite(uses=args.uses,hours=args.hours))

if __name__=='__main__': main()
