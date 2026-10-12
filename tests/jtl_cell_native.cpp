#include <vector>
#include <stdexcept>
#include <iostream>
struct SceneObject;
struct Parent {SceneObject*value=nullptr;SceneObject*get(){return value;}SceneObject*operator->(){return value;}operator bool()const{return value!=nullptr;}};
struct WeakParent {Parent value;Parent get(){return value;}};
struct SceneObject {Parent parent;WeakParent getParent(){return {parent};}virtual bool isCellObject(){return false;}virtual ~SceneObject()=default;};
struct CellObject:SceneObject {int number;CellObject(int n):number(n){}bool isCellObject()override{return true;}int getCellNumber(){return number;}};
struct ShipObject {bool pob=true;int lookups=0;std::vector<CellObject*> cells;bool isPobShip(){return pob;}ShipObject*asPobShip(){return this;}int getTotalCellNumber(){return cells.size();}CellObject*getCell(int i){++lookups;return cells.at(i);}};
struct CreatureObject {ShipObject*ship=nullptr;Parent parent;WeakParent getParent(){return {parent};}};
#include "jtl_cell_native.inc"
int checks=0;
void check(bool ok){++checks;if(!ok)throw std::runtime_error("Native ship cell check "+std::to_string(checks));}
int main(){
 ShipObject yacht,other;CellObject bridge(1),room(2),starport(16);yacht.cells={&bridge,&room};CreatureObject c;c.parent.value=&starport;
 check(NativeJtl::playerCell(&c,&yacht)==nullptr && yacht.lookups==0);
 c.parent.value=&bridge;check(NativeJtl::playerCell(&c,&yacht)==nullptr && yacht.lookups==0);
 c.ship=&other;check(NativeJtl::playerCell(&c,&yacht)==nullptr && yacht.lookups==0);
 c.ship=&yacht;c.parent.value=&room;check(NativeJtl::playerCell(&c,&yacht)==&room);
 SceneObject chair;chair.parent.value=&room;c.parent.value=&chair;check(NativeJtl::playerCell(&c,&yacht)==&room);
 c.parent.value=nullptr;check(NativeJtl::playerCell(&c,&yacht)==&bridge);
 c.parent.value=&starport;auto before=yacht.lookups;bool denied=false;try{NativeJtl::playerCell(&c,&yacht);}catch(const std::runtime_error&){denied=true;}
 check(denied && yacht.lookups==before);
 yacht.pob=false;check(NativeJtl::playerCell(&c,&yacht)==nullptr && yacht.lookups==before);
 std::cout<<checks<<" native ship containment/bounds checks passed\n";
}
