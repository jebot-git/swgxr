#ifndef SWGXR_SLICING_PUZZLE_H
#define SWGXR_SLICING_PUZZLE_H
#include <algorithm>
#include <array>
#include <random>
#include <queue>
#include <set>
#include <string>
#include <vector>
namespace SwgxrSlicingPuzzle {
using Cell=std::array<int,3>;
struct End {Cell cell,face;};
struct Pair {int color;End a,b;};
struct Wire {int color;std::vector<Cell> cells;};
struct Board {int size;std::vector<Pair> pairs;std::vector<Wire> preconnected,witness;};
inline int index(const Cell& c,int n){return c[0]+n*(c[1]+n*c[2]);}
inline bool inside(const Cell& c,int n){return c[0]>=0&&c[0]<n&&c[1]>=0&&c[1]<n&&c[2]>=0&&c[2]<n;}
inline int distance(const Cell& a,const Cell& b){return std::abs(a[0]-b[0])+std::abs(a[1]-b[1])+std::abs(a[2]-b[2]);}
inline bool endpoint(const End& e,int n){int norm=0;for(int a=0;a<3;++a){norm+=std::abs(e.face[a]);if(e.face[a] && (std::abs(e.face[a])!=1 || e.cell[a]!=(e.face[a]<0?0:n-1)))return false;}return inside(e.cell,n)&&norm==1;}
inline bool validate(const Board& b,const std::vector<Wire>& wires,std::string* why=nullptr){
 auto fail=[&](const char* reason){if(why)*why=reason;return false;};
 if(b.size<3||b.size>5||b.pairs.size()<2||b.pairs.size()>4||wires.size()!=b.pairs.size())return fail("incomplete_paths");
 std::set<int> used,colors;int n=b.size;
 for(auto& w:wires){
  auto p=std::find_if(b.pairs.begin(),b.pairs.end(),[&](const Pair& v){return v.color==w.color;});
  if(p==b.pairs.end()||!colors.insert(w.color).second||w.cells.size()<2||w.cells.size()>size_t(n*n*n))return fail("invalid_color_or_length");
  if(!endpoint(p->a,n)||!endpoint(p->b,n))return fail("invalid_endpoint");
  if(!((w.cells.front()==p->a.cell&&w.cells.back()==p->b.cell)||(w.cells.front()==p->b.cell&&w.cells.back()==p->a.cell)))return fail("endpoints_not_connected");
  for(size_t i=0;i<w.cells.size();++i){if(!inside(w.cells[i],n))return fail("cell_out_of_bounds");if(!used.insert(index(w.cells[i],n)).second)return fail("cell_shared_or_repeated");if(i&&distance(w.cells[i-1],w.cells[i])!=1)return fail("nonadjacent_cells");}
 }
 return true;
}
inline Board generate(int size,int colors,unsigned int seed){
 Board b;b.size=std::max(3,std::min(5,size));colors=std::max(2,std::min(4,colors));std::mt19937 rng(seed);int n=b.size;
 std::array<int,3> axes{{0,1,2}},flip{{int(rng()%2),int(rng()%2),int(rng()%2)}};std::shuffle(axes.begin(),axes.end(),rng);
 auto transform=[&](Cell c){Cell o;for(int a=0;a<3;++a)o[axes[a]]=flip[a]?n-1-c[a]:c[a];return o;};
 auto face=[&](Cell c){Cell f{{0,0,0}};int sign=c[0]==0?-1:1;f[axes[0]]=flip[0]?-sign:sign;return f;};
 std::vector<Cell> layer,snake;for(int y=0;y<n;++y)for(int x=0;x<n;++x)layer.push_back(Cell{{y%2?n-1-x:x,y,0}});
 for(int z=0;z<n;++z)for(int i=0;i<n*n;++i){auto c=layer[z%2?n*n-1-i:i];c[2]=z;snake.push_back(c);}
 std::vector<int> cuts;for(int row=1;row<n*n;++row)cuts.push_back(row);std::shuffle(cuts.begin(),cuts.end(),rng);cuts.resize(colors-1);cuts.push_back(0);cuts.push_back(n*n);std::sort(cuts.begin(),cuts.end());
 std::set<int> allEnds;
 for(int color=0;color<colors;++color){int from=cuts[color]*n,to=cuts[color+1]*n-1;Pair p{color,{transform(snake[from]),face(snake[from])},{transform(snake[to]),face(snake[to])}};b.pairs.push_back(p);allEnds.insert(index(p.a.cell,n));allEnds.insert(index(p.b.cell,n));Wire w{color,{}};for(int i=from;i<=to;++i)w.cells.push_back(transform(snake[i]));b.witness.push_back(w);}
 // Editable preconnections never constrain solvability: the retained disjoint
 // witness remains a solution after cutting them. Some take a wrong first turn.
 std::set<int> occupied;int full=0;
 for(int color=0;color<colors;++color){if(rng()%4==0)continue;auto& solution=b.witness[color];Wire w{color,{solution.cells.front()}};
  if(full<colors-1 && rng()%2==0){
   // Random breadth-first route can cross another color's hidden solution;
   // detaching it restores that solution. All other endpoints stay unoccupied.
   std::vector<int> previous(n*n*n,-1);std::queue<Cell> pending;pending.push(solution.cells.front());previous[index(solution.cells.front(),n)]=-2;
   while(!pending.empty() && previous[index(solution.cells.back(),n)]==-1){auto at=pending.front();pending.pop();std::array<int,6> order{{0,1,2,3,4,5}};std::shuffle(order.begin(),order.end(),rng);for(int d:order){auto c=at;c[d/2]+=d%2?1:-1;if(!inside(c,n))continue;int i=index(c,n);if(previous[i]!=-1 || occupied.count(i) || (allEnds.count(i)&&c!=solution.cells.back()))continue;previous[i]=index(at,n);pending.push(c);}}
   int last=index(solution.cells.back(),n);if(previous[last]!=-1){w.cells.clear();for(int i=last;i>=0;i=previous[i])w.cells.push_back(Cell{{i%n,(i/n)%n,i/(n*n)}});std::reverse(w.cells.begin(),w.cells.end());++full;}
  }
  if(w.cells.size()==1){auto next=solution.cells[1];if(rng()%2==0){std::vector<Cell> alternatives;for(int axis=0;axis<3;++axis)for(int direction:{-1,1}){auto c=w.cells[0];c[axis]+=direction;if(inside(c,n)&&c!=next&&!allEnds.count(index(c,n))&&!occupied.count(index(c,n)))alternatives.push_back(c);}if(!alternatives.empty())next=alternatives[rng()%alternatives.size()];}if(occupied.count(index(next,n))||allEnds.count(index(next,n)))continue;w.cells.push_back(next);}
  if(occupied.count(index(w.cells[0],n)))continue;
  for(auto& c:w.cells)occupied.insert(index(c,n));
  b.preconnected.push_back(w);
 }

 return b;
}
}
#endif
